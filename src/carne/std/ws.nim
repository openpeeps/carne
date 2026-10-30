# Carne std/ws: async + sync WebSocket client and server via powpow.
#
#   const ws = require("std/ws");
#   const srv = ws.serve(8080, {onMessage: (conn, msg) => conn.send("hi " + msg.data)});
#   const c = await ws.connect("ws://127.0.0.1:8080/chat");  // -> established handle
#   c.send("hello");
#   const c2 = ws.connectSync("ws://127.0.0.1:8080/chat");  // blocks until open
#   c.close(); ws.close(srv.port);
#
# connect returns a Promise for the connection handle: `await
# ws.connect(url[, handlers])` or `ws.connect(url).then(c => ...)`. The
# handshake runs on the run's shared powpow loop (no threads), so it
# composes with timers and std/http. connectSync blocks, pumping the same
# loop until the handshake completes, then returns an established handle.
# serve borrows the loop and holds it alive until close (Node semantics).
# Both connect forms take handshake opts in the same object as the
# handlers: {headers?, protocols?, timeoutMs?, pingIntervalMs?,
# idleTimeoutMs?, maxFrameSize?, onOpen?, onMessage?, onClose?, onError?}.
#
# Handles are `{send(text[, {binary}]), ping([data]), protocol(), close([code[, reason]])}`.
# Messages arrive as `{data, isBinary}`; closes as `{code, reason}`;
# errors as `{message}`. Bodies are UTF-8 strings in v1; binary frames
# are delivered as strings with isBinary: true, and sent with
# `send(text, {binary: true})` (no TypedArrays in v1). `ping()` sends a
# control ping (the peer's pong is answered internally). `protocol()`
# returns the subprotocol the server selected ("" when none).
# Server callbacks get `(conn, payload)`, client callbacks just `(payload)`
# (onOpen takes no arguments).
# wss:// clients are supported via a per-run shared TLS context with
# system CAs (same pattern as std/http); serving wss:// needs cert
# loading and is out of scope in v1.
#
# connect() reports handshake failures by rejecting its promise (like
# std/http fetch); an onError handler fires too when given. Without a
# promise rejection path (pure handler use with no await/catch), errors
# with no onError handler become the run's uncaught error. close() is
# final: no onClose fires for locally-closed connections, and every form
# of close is idempotent. Pumping the shared loop inside connectSync may
# run due timers and settle other in-flight work early; that is inherent
# to a blocking call on a single-threaded loop.

import std/[json, monotimes, strutils, tables, times]

import javascriptcore

import powpow/proto/ws
from powpow/loop import addTimer, poll, stop
from powpow/net/tls import SslContext, newClientTlsContext

import ../bridge
import ../modules

const
  DefaultWsTimeoutMs = 10_000
  WsSyncSliceMs = 25

type
  SyncState = ref object
    done: bool
    ok: bool
    msg: string

  ConnEntry = object
    ctx: JSContextRef
    rt: Runtime
    ws: WsConnection
    handle: JSObjectRef
    onOpen, onMessage, onClose, onError: JSObjectRef
    resolveFn, rejectFn: JSObjectRef
    serverKey: pointer
    closing: bool
    closed: bool
    openOk: bool
    sync: SyncState

  ServerEntry = object
    ctx: JSContextRef
    rt: Runtime
    server: WsServer
    onOpen, onMessage, onClose, onError: JSObjectRef
    port: int
    host: string

var wsConns {.threadvar.}: Table[pointer, ConnEntry]
var wsServers {.threadvar.}: Table[pointer, ServerEntry]
var wsTlsCtxs {.threadvar.}: Table[pointer, SslContext]
  ## One shared client TLS context per run for wss:// connects, freed
  ## from the table by closeAllWs at teardown (the context itself is GC'd).

var wsFireDepth {.threadvar.}: int
  ## >0 while a user callback runs inside a powpow dispatcher. Destroying
  ## a server synchronously at that point crashes powpow's in-progress
  ## dispatch (its close frame path touches ws.conn after notifyClose
  ## returns); close(port) defers the server close to the next loop turn
  ## instead (see queueServerClose).
var wsClosing {.threadvar.}: seq[WsServer]
  ## Servers with deferred closes outstanding (see queueServerClose).

proc decPending(rt: Runtime) =
  dec rt.pending
  if rt.pending <= 0 and not rt.exitRequested:
    rt.pending = 0
    rt.loop.stop()

proc tlsCtxFor(rt: Runtime): SslContext =
  ## The run's shared client TLS context for wss://, created lazily on
  ## first use. nil when OpenSSL init fails (callers throw for wss://).
  ## Plain-ws runs never pay OpenSSL init.
  let key = cast[pointer](rt)
  if wsTlsCtxs.hasKey(key):
    return wsTlsCtxs[key]
  try:
    result = newClientTlsContext()
  except CatchableError:
    result = nil
  wsTlsCtxs[key] = result

proc fireCb(c: JSContextRef; rt: Runtime; fn: JSObjectRef;
    args: varargs[JSValueRef]) =
  ## Calls one user callback; a JS throw becomes the run's uncaught error.
  if fn == nil:
    return
  var ex: JSValueRef = nil
  inc wsFireDepth
  try:
    if args.len == 0:
      discard JSObjectCallAsFunction(c, fn, nil, 0, nil, addr ex)
    else:
      var argv = newSeq[JSValueRef](args.len)
      for i in 0 ..< args.len:
        argv[i] = args[i]
      discard JSObjectCallAsFunction(c, fn, nil, csize_t(args.len),
        addr argv[0], addr ex)
  finally:
    dec wsFireDepth
  if ex != nil:
    if rt.uncaught.len == 0:
      rt.uncaught = valueToString(c, ex)
      rt.exitCode = 1

proc unprotectHandlers(ctx: JSContextRef; fns: varargs[JSObjectRef]) =
  for f in fns:
    if f != nil:
      JSValueUnprotect(ctx, f)

proc cleanupConn(key: pointer) =
  ## Releases one pending slot and drops the entry with all its protected
  ## JS refs. Safe to call twice (closed flag) and safe with missing keys
  ## (late powpow events after teardown).
  if not wsConns.hasKey(key):
    return
  var e = wsConns[key]
  let c = e.ctx
  let h = e.handle
  let fns = [e.onOpen, e.onMessage, e.onClose, e.onError,
    e.resolveFn, e.rejectFn]
  if not e.closed:
    e.closed = true
    wsConns[key] = e
    decPending(e.rt)
  wsConns.del(key)
  if h != nil:
    JSValueUnprotect(c, h)
  unprotectHandlers(c, fns[0], fns[1], fns[2], fns[3], fns[4], fns[5])

proc settleResolve(c: JSContextRef; res, rej: JSObjectRef; val: JSValueRef) =
  ## Resolves a connect() promise with the handle; settle fns are consumed.
  if res == nil:
    return
  var ex: JSValueRef = nil
  var a = val
  discard JSObjectCallAsFunction(c, res, nil, 1, addr a, addr ex)
  JSValueUnprotect(c, res)
  if rej != nil:
    JSValueUnprotect(c, rej)

proc settleReject(c: JSContextRef; res, rej: JSObjectRef; msg: string) =
  ## Rejects a connect() promise with an Error; settle fns are consumed.
  if rej == nil:
    if res != nil:
      JSValueUnprotect(c, res)
    return
  var ex: JSValueRef = nil
  let msgV = toJS(c, msg)
  let errObj = JSObjectMakeError(c, 1, unsafeAddr msgV, addr ex)
  var arg = if errObj != nil: errObj else: msgV
  discard JSObjectCallAsFunction(c, rej, nil, 1, addr arg, addr ex)
  if res != nil:
    JSValueUnprotect(c, res)
  JSValueUnprotect(c, rej)

proc failAsync(key: pointer; msg: string) =
  ## Terminal pre-open failure on the async path: releases the slot, keeps
  ## the entry so send/close report "closed", notifies sync waiters.
  if not wsConns.hasKey(key):
    return
  var e = wsConns[key]
  if e.sync != nil and not e.sync.done:
    e.sync.done = true
    e.sync.ok = false
    e.sync.msg = msg
  let c = e.ctx
  let res = e.resolveFn
  let rej = e.rejectFn
  e.resolveFn = nil
  e.rejectFn = nil
  if not e.closed:
    e.closed = true
    decPending(e.rt)
  wsConns[key] = e
  if res != nil or rej != nil:
    settleReject(c, res, rej, "connect: " & msg)

proc wsOnOpen(ws: WsConnection) {.gcsafe.} =
  ## powpow dispatch: loop thread is the JS thread (borrowed loop).
  {.cast(gcsafe).}:
    let key = cast[pointer](ws)
    if not wsConns.hasKey(key):
      try:
        ws.closeWs(1000, "")
      except CatchableError:
        discard
      return
    var e = wsConns[key]
    if e.closing:
      # close() was called while the handshake was in flight. Clear the
      # settle fns first so cleanupConn does not unprotect them out from
      # under the settle below.
      let c = e.ctx
      let res = e.resolveFn
      let rej = e.rejectFn
      e.resolveFn = nil
      e.rejectFn = nil
      wsConns[key] = e
      cleanupConn(key)
      try:
        ws.closeWs(1000, "")
      except CatchableError:
        discard
      if e.sync != nil and not e.sync.done:
        e.sync.done = true
        e.sync.ok = false
        e.sync.msg = "connection closed"
      elif res != nil or rej != nil:
        settleReject(c, res, rej, "connect: connection closed")
      return
    if e.sync != nil and not e.sync.done:
      e.sync.done = true
      e.sync.ok = true
    # Ready for send: client conns open here; server-side entries are
    # created open (see serve).
    e.openOk = true
    let c = e.ctx
    let res = e.resolveFn
    let rej = e.rejectFn
    let handle = e.handle
    e.resolveFn = nil
    e.rejectFn = nil
    wsConns[key] = e
    if res != nil or rej != nil:
      settleResolve(c, res, rej, handle)
    if e.serverKey == nil:
      fireCb(e.ctx, e.rt, e.onOpen)
    else:
      fireCb(e.ctx, e.rt, e.onOpen, e.handle)

proc wsOnMessage(ws: WsConnection; kind: WsFrameKind;
    data: openArray[byte]) {.gcsafe.} =
  ## Only complete text/binary messages arrive here: powpow reassembles
  ## fragments, auto-pongs pings and answers closes internally.
  {.cast(gcsafe).}:
    let key = cast[pointer](ws)
    if not wsConns.hasKey(key):
      return
    let e = wsConns[key]
    if e.closing or e.onMessage == nil:
      return
    var s = newString(data.len)
    if data.len > 0:
      copyMem(addr s[0], unsafeAddr data[0], data.len)
    let msg = jsonToJS(e.ctx,
      %*{"data": s, "isBinary": kind == wsBinary})
    if msg == nil:
      return
    if e.serverKey == nil:
      fireCb(e.ctx, e.rt, e.onMessage, msg)
    else:
      fireCb(e.ctx, e.rt, e.onMessage, e.handle, msg)

proc wsOnClose(ws: WsConnection; code: int; reason: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    let key = cast[pointer](ws)
    if not wsConns.hasKey(key):
      return
    var ne = wsConns[key]
    let wasClosing = ne.closing
    let sync = ne.sync
    let c = ne.ctx
    let res = ne.resolveFn
    let rej = ne.rejectFn
    ne.resolveFn = nil
    ne.rejectFn = nil
    wsConns[key] = ne
    cleanupConn(key)
    if sync != nil and not sync.done:
      sync.done = true
      sync.ok = false
      sync.msg = "connection closed before open"
      return
    if res != nil or rej != nil:
      settleReject(c, res, rej, "connect: connection closed before open")
      return
    if wasClosing:
      return
    let ev = jsonToJS(ne.ctx, %*{"code": code, "reason": reason})
    if ev == nil:
      return
    if ne.serverKey == nil:
      fireCb(ne.ctx, ne.rt, ne.onClose, ev)
    else:
      fireCb(ne.ctx, ne.rt, ne.onClose, ne.handle, ev)

proc wsOnError(ws: WsConnection; err: string) {.gcsafe.} =
  {.cast(gcsafe).}:
    let key = cast[pointer](ws)
    if not wsConns.hasKey(key):
      return
    var e = wsConns[key]
    if e.closing:
      let c = e.ctx
      let res = e.resolveFn
      let rej = e.rejectFn
      e.resolveFn = nil
      e.rejectFn = nil
      wsConns[key] = e
      cleanupConn(key)
      if e.sync != nil and not e.sync.done:
        e.sync.done = true
        e.sync.ok = false
        e.sync.msg = err
      elif res != nil or rej != nil:
        settleReject(c, res, rej, "connect: " & err)
      return
    if not ws.isEstablished():
      # Pre-open failure (DNS, TCP refused, bad handshake): terminal.
      let sync = e.sync
      let c = e.ctx
      let r = e.rt
      let sk = e.serverKey
      let errFn = e.onError
      let hadPromise = e.resolveFn != nil or e.rejectFn != nil
      failAsync(key, err)
      if sync != nil:
        return
      if errFn != nil:
        let ev = jsonToJS(c, %*{"message": err})
        if ev == nil:
          return
        if sk == nil:
          fireCb(c, r, errFn, ev)
        else:
          fireCb(c, r, errFn, wsConns[key].handle, ev)
      elif not hadPromise and r.uncaught.len == 0:
        # No promise and no handler: nowhere else to report (with a
        # promise, the rejection carries it, like std/http fetch).
        r.uncaught = "ws: " & err
        r.exitCode = 1
      return
    # Post-open transport error: report, keep the conn (a close follows).
    if e.onError != nil:
      let ev = jsonToJS(e.ctx, %*{"message": err})
      if ev == nil:
        return
      if e.serverKey == nil:
        fireCb(e.ctx, e.rt, e.onError, ev)
      else:
        fireCb(e.ctx, e.rt, e.onError, e.handle, ev)
    elif e.rt.uncaught.len == 0:
      e.rt.uncaught = "ws: " & err
      e.rt.exitCode = 1

proc readOneFn(ctx: JSContextRef; obj: JSValueRef; key, name: string;
    exception: ptr JSValueRef; ok: var bool;
    docBlock = ""): JSObjectRef =
  ## Reads one optional handler fn; nil for absent/undefined. Protects the
  ## result. ok=false with a JS throw on anything else.
  template oerr(msg: string): untyped =
    throwError(ctx,
      (if docBlock.len > 0: docBlock & "\n" else: "") & msg, exception)
  result = nil
  ok = true
  var err = ""
  let f = getField(ctx, obj, key, err)
  if err != "":
    oerr(name & ": handlers." & key & " " & err)
    ok = false
    return
  if f.kind == nvkUndefined:
    return
  if f.kind != nvkFunction:
    oerr(name & ": handlers." & key & " is not a function, got " &
      jsTypeName(f.kind))
    ok = false
    return
  result = f.raw
  JSValueProtect(ctx, result)

proc readHandlers(ctx: JSContextRef; obj: JSValueRef; name: string;
    exception: ptr JSValueRef; onOpen, onMessage, onClose,
    onError: var JSObjectRef; docBlock = ""): bool =
  ## Reads optional {onOpen?, onMessage?, onClose?, onError?} handler fns.
  ## nil obj means absent. True on success.
  onOpen = nil
  onMessage = nil
  onClose = nil
  onError = nil
  if obj == nil:
    return true
  var ok = false
  onOpen = readOneFn(ctx, obj, "onOpen", name, exception, ok, docBlock)
  if not ok:
    return false
  onMessage = readOneFn(ctx, obj, "onMessage", name, exception, ok,
    docBlock)
  if not ok:
    unprotectHandlers(ctx, onOpen)
    return false
  onClose = readOneFn(ctx, obj, "onClose", name, exception, ok, docBlock)
  if not ok:
    unprotectHandlers(ctx, onOpen, onMessage)
    return false
  onError = readOneFn(ctx, obj, "onError", name, exception, ok, docBlock)
  if not ok:
    unprotectHandlers(ctx, onOpen, onMessage, onClose)
    return false
  true

proc findConnByHandle(handle: JSObjectRef): pointer =
  for k, e in wsConns.pairs:
    if e.handle == handle:
      return k
  nil

registerFn(ctx, connSend(text: string, optsObj ?: JSObjectRef)):
  ## conn.send(text[, {binary}]): thisObject is the handle created by connect/serve.
  if thisObject == nil or not JSValueIsObject(ctx, thisObject):
    throwError(ctx, "send: called on an invalid connection", exception)
    return nil
  let key = findConnByHandle(thisObject)
  if key == nil:
    throwError(ctx, "send: connection is closed", exception)
    return nil
  let e = wsConns[key]
  if e.closing or e.closed or e.ws == nil or not e.openOk:
    throwError(ctx, "send: connection is closed", exception)
    return nil
  var binary = false
  if optsObj != nil:
    var berr = ""
    let b = getField(ctx, optsObj, "binary", berr)
    if berr != "":
      throwError(ctx, "send: options.binary " & berr, exception)
      return nil
    if b.kind == nvkBool:
      binary = b.b
    elif b.kind != nvkUndefined:
      throwError(ctx, "send: options.binary must be a boolean", exception)
      return nil
  try:
    if binary:
      # Strings are UTF-8 bytes on the wire here (no TypedArrays in v1).
      if text.len > 0:
        e.ws.sendBinary(text.toOpenArrayByte(0, text.high))
      else:
        e.ws.sendBinary([])
    else:
      e.ws.sendMessage(text)
  except CatchableError as err:
    throwError(ctx, "send: " & err.msg, exception)
    return nil
  toJS(ctx, true)

registerFn(ctx, connClose(code: default(int64, 1000), reason ?: string)):
  ## conn.close([code[, reason]]): final, idempotent; the pending slot is
  ## released when the close lands (or at teardown).
  if thisObject == nil or not JSValueIsObject(ctx, thisObject):
    throwError(ctx, "close: called on an invalid connection", exception)
    return nil
  let key = findConnByHandle(thisObject)
  if key == nil:
    return toJS(ctx, true)
  var e = wsConns[key]
  if code < 1000 or code > 4999:
    throwError(ctx, "close: code must be 1000..4999", exception)
    return nil
  let codeNum = int(code)
  if e.ws == nil or e.ws.conn == nil:
    # Nothing on the wire yet: no close event will ever arrive, so release
    # now. A late loop.connect still lands safely: its dispatcher finds a
    # missing entry and shuts the conn down. A pending connect() promise
    # rejects: the user closed before open.
    let c = e.ctx
    let res = e.resolveFn
    let rej = e.rejectFn
    e.resolveFn = nil
    e.rejectFn = nil
    wsConns[key] = e
    cleanupConn(key)
    if res != nil or rej != nil:
      settleReject(c, res, rej, "connect: connection closed")
    return toJS(ctx, true)
  e.closing = true
  wsConns[key] = e
  try:
    e.ws.closeWs(codeNum, reason)
  except CatchableError:
    discard
  toJS(ctx, true)

registerFn(ctx, connPing(data ?: string)):
  ## conn.ping([data]): send a control ping; the peer's pong is answered internally.
  if thisObject == nil or not JSValueIsObject(ctx, thisObject):
    throwError(ctx, "ping: called on an invalid connection", exception)
    return nil
  let key = findConnByHandle(thisObject)
  if key == nil:
    throwError(ctx, "ping: connection is closed", exception)
    return nil
  let e = wsConns[key]
  if e.closing or e.closed or e.ws == nil or not e.openOk:
    throwError(ctx, "ping: connection is closed", exception)
    return nil
  try:
    if data.len > 0:
      e.ws.sendPing(data.toOpenArrayByte(0, data.high))
    else:
      e.ws.sendPing()
  except CatchableError as err:
    throwError(ctx, "ping: " & err.msg, exception)
    return nil
  toJS(ctx, true)

registerFn(ctx, connProtocol()):
  ## conn.protocol(): the subprotocol the server selected ("" when none).
  if thisObject == nil or not JSValueIsObject(ctx, thisObject):
    throwError(ctx, "protocol: called on an invalid connection", exception)
    return nil
  let key = findConnByHandle(thisObject)
  if key == nil:
    throwError(ctx, "protocol: connection is closed", exception)
    return nil
  let e = wsConns[key]
  if e.ws == nil:
    throwError(ctx, "protocol: connection is closed", exception)
    return nil
  var proto = ""
  try:
    proto = e.ws.getProtocol()
  except CatchableError as err:
    throwError(ctx, "protocol: " & err.msg, exception)
    return nil
  toJS(ctx, proto)

proc makeConnHandle(ctx: JSContextRef; exception: ptr JSValueRef): JSObjectRef =
  ## Fresh `{send, ping, protocol, close}` handle; caller protects it
  ## via the entry.
  result = newObject(ctx)
  var ex: JSValueRef = nil
  setProp(ctx, result, "send", makeFunction(ctx, "send", connSend),
    addr ex)
  if ex != nil:
    throwError(ctx, "ws: could not create connection handle", exception)
    return nil
  setProp(ctx, result, "ping", makeFunction(ctx, "ping", connPing),
    addr ex)
  if ex != nil:
    throwError(ctx, "ws: could not create connection handle", exception)
    return nil
  setProp(ctx, result, "protocol", makeFunction(ctx, "protocol",
    connProtocol), addr ex)
  if ex != nil:
    throwError(ctx, "ws: could not create connection handle", exception)
    return nil
  setProp(ctx, result, "close", makeFunction(ctx, "close", connClose),
    addr ex)
  if ex != nil:
    throwError(ctx, "ws: could not create connection handle", exception)
    return nil

proc insertConn(ctx: JSContextRef; rt: Runtime; ws: WsConnection;
    serverKey: pointer; onOpen, onMessage, onClose, onError: JSObjectRef;
    resolveFn, rejectFn: JSObjectRef; sync: SyncState;
    exception: ptr JSValueRef): JSObjectRef =
  ## Builds the handle, protects everything, registers the entry and holds
  ## one pending slot. Settle fns arrive pre-protected (ownership moves
  ## here). Nil on failure (everything already unprotected).
  let handle = makeConnHandle(ctx, exception)
  if handle == nil:
    unprotectHandlers(ctx, onOpen, onMessage, onClose, onError,
      resolveFn, rejectFn)
    return nil
  JSValueProtect(ctx, handle)
  let key = cast[pointer](ws)
  wsConns[key] = ConnEntry(ctx: ctx, rt: rt, ws: ws, handle: handle,
    onOpen: onOpen, onMessage: onMessage, onClose: onClose,
    onError: onError, resolveFn: resolveFn, rejectFn: rejectFn,
    serverKey: serverKey, closing: false, closed: false,
    openOk: false, sync: sync)
  inc rt.pending
  handle

type
  WsConnectOpts = object
    headers: seq[(string, string)]
    protocols: seq[string]
    timeoutMs: int
    pingIntervalMs: int
    idleTimeoutMs: int
    maxFrameSize: int

proc defaultConnectOpts(): WsConnectOpts =
  WsConnectOpts(headers: @[], protocols: @[],
    timeoutMs: DefaultWsTimeoutMs, pingIntervalMs: 0, idleTimeoutMs: 0,
    maxFrameSize: DefaultMaxFrameSize)

proc connectOptNum(ctx: JSContextRef; obj: JSValueRef; name, key: string;
    defaultVal: int; allowZero: bool): int =
  ## One numeric connect opt, `defaultVal` when absent/undefined. Raises
  ## on anything malformed (callers turn it into a sync JS throw).
  var err = ""
  let f = getField(ctx, obj, key, err)
  if err != "":
    raise newException(CatchableError, name & ": options." & key & " " & err)
  if f.kind == nvkUndefined:
    return defaultVal
  var v = defaultVal
  case f.kind
  of nvkInt: v = int(f.i)
  of nvkFloat: v = int(f.f)
  else:
    raise newException(CatchableError,
      name & ": options." & key & " must be a number")
  if v < 0 or (v == 0 and not allowZero):
    raise newException(CatchableError, name & ": options." & key &
      (if allowZero: " must be >= 0" else: " must be positive"))
  v

proc parseConnectOpts(ctx: JSContextRef; obj: JSValueRef; name: string):
    WsConnectOpts =
  ## Reads {headers?, protocols?, timeoutMs?, pingIntervalMs?,
  ## idleTimeoutMs?, maxFrameSize?} from the connect opts object (which
  ## may also carry the onXxx handlers — those are read separately).
  ## Raises on anything malformed. nil obj means all defaults.
  result = defaultConnectOpts()
  if obj == nil:
    return
  result.timeoutMs = connectOptNum(ctx, obj, name, "timeoutMs",
    DefaultWsTimeoutMs, false)
  result.pingIntervalMs = connectOptNum(ctx, obj, name, "pingIntervalMs",
    0, true)
  result.idleTimeoutMs = connectOptNum(ctx, obj, name, "idleTimeoutMs",
    0, true)
  result.maxFrameSize = connectOptNum(ctx, obj, name, "maxFrameSize",
    DefaultMaxFrameSize, false)
  var err = ""
  let h = getField(ctx, obj, "headers", err)
  if err != "":
    raise newException(CatchableError, name & ": options.headers " & err)
  if h.kind != nvkUndefined:
    if h.kind != nvkObject:
      raise newException(CatchableError,
        name & ": options.headers must be an object")
    for k, hv in h.obj.pairs:
      if hv.kind != nvkString:
        raise newException(CatchableError,
          name & ": header \"" & k & "\" must be a string")
      result.headers.add((k, hv.s))
  let p = getField(ctx, obj, "protocols", err)
  if err != "":
    raise newException(CatchableError, name & ": options.protocols " & err)
  if p.kind != nvkUndefined:
    if p.kind != nvkArray:
      raise newException(CatchableError,
        name & ": options.protocols must be an array of strings")
    for item in p.arr:
      if item.kind != nvkString:
        raise newException(CatchableError,
          name & ": options.protocols must be an array of strings")
      let proto = item.s.strip()
      if proto.len > 0:
        result.protocols.add(proto)

proc parseWsTarget(url: string; name: string): tuple[host: string, port: int,
    path: string, tls: bool] =
  ## Splits a ws:// or wss:// URL; raises on anything else (callers turn
  ## it into a sync JS throw).
  try:
    let t = parseWsUrl(url)
    (t.host, t.port, t.path, t.tls)
  except WsError as e:
    raise newException(CatchableError, name & ": " & e.msg)

proc startClient(ctx: JSContextRef; rt: Runtime; url: string; name: string;
    onOpen, onMessage, onClose, onError: JSObjectRef;
    resolveFn, rejectFn: JSObjectRef; sync: SyncState; copts: WsConnectOpts;
    exception: ptr JSValueRef): JSObjectRef =
  ## Shared connect core: parses the URL, arms connectWs on the run's loop,
  ## registers the entry. Handlers and settle fns are consumed (protected
  ## or freed) here.
  var host, path: string
  var port: int
  var tls = false
  try:
    (host, port, path, tls) = parseWsTarget(url, name)
  except CatchableError as e:
    unprotectHandlers(ctx, onOpen, onMessage, onClose, onError,
      resolveFn, rejectFn)
    throwError(ctx, e.msg, exception)
    return nil
  var tlsCtx: SslContext = nil
  if tls:
    tlsCtx = tlsCtxFor(rt)
    if tlsCtx == nil:
      unprotectHandlers(ctx, onOpen, onMessage, onClose, onError,
        resolveFn, rejectFn)
      throwError(ctx,
        name & ": wss:// needs a TLS context (OpenSSL init failed)",
        exception)
      return nil
  let loop = rt.ensureLoop()
  var ws: WsConnection
  try:
    ws = connectWs(loop, host, port, path, host, onOpen = wsOnOpen,
      onMessage = wsOnMessage, onClose = wsOnClose, onError = wsOnError,
      maxFrameSize = copts.maxFrameSize,
      handshakeTimeoutMs = copts.timeoutMs, tlsCtx = tlsCtx,
      extraHeaders = copts.headers, protocols = copts.protocols,
      pingIntervalMs = copts.pingIntervalMs,
      idleTimeoutMs = copts.idleTimeoutMs)
  except CatchableError as e:
    unprotectHandlers(ctx, onOpen, onMessage, onClose, onError,
      resolveFn, rejectFn)
    throwError(ctx, name & ": " & e.msg, exception)
    return nil
  insertConn(ctx, rt, ws, nil, onOpen, onMessage, onClose, onError,
    resolveFn, rejectFn, sync, exception)

proc queueServerClose(rt: Runtime; server: WsServer) =
  ## Finishes a ws.close(port) whose caller sits inside a user callback:
  ## the server close runs on the next loop turn, after powpow's dispatch
  ## stack has unwound. Exactly-once via wsClosing (teardown drains it).
  wsClosing.add(server)
  let srv = server
  let loop = rt.ensureLoop()
  discard loop.addTimer(1) do (id: int):
    var idx = -1
    for i in 0 ..< wsClosing.len:
      if wsClosing[i] == srv:
        idx = i
        break
    if idx >= 0:
      wsClosing.del(idx)
      try:
        srv.close()
      except CatchableError:
        discard
proc closeAllWs*() =
  ## Closes every live server and connection. Runs at runtime teardown with
  ## entries removed first, so late powpow close events no-op instead of
  ## calling JS on a dying context. Safe with none live.
  var skeys: seq[pointer] = @[]
  for k in wsServers.keys:
    skeys.add(k)
  for k in skeys:
    if not wsServers.hasKey(k):
      continue
    let se = wsServers[k]
    unprotectHandlers(se.ctx, se.onOpen, se.onMessage, se.onClose,
      se.onError)
    wsServers.del(k)
    try:
      se.server.close()
    except CatchableError:
      discard
    decPending(se.rt)
  # Deferred closes that never fired (loop drained first): run them now.
  for srv in wsClosing:
    try:
      srv.close()
    except CatchableError:
      discard
  wsClosing.setLen(0)
  var tkeys: seq[pointer] = @[]
  for k in wsTlsCtxs.keys:
    tkeys.add(k)
  for k in tkeys:
    wsTlsCtxs.del(k)
  var ckeys: seq[pointer] = @[]
  for k in wsConns.keys:
    ckeys.add(k)
  for k in ckeys:
    if not wsConns.hasKey(k):
      continue
    let e = wsConns[k]
    wsConns.del(k)
    if not e.closed:
      decPending(e.rt)
    if e.handle != nil:
      JSValueUnprotect(e.ctx, e.handle)
    unprotectHandlers(e.ctx, e.onOpen, e.onMessage, e.onClose, e.onError)
    if e.ws != nil and e.ws.conn != nil:
      try:
        e.ws.closeWs(1000, "")
      except CatchableError:
        discard

# Teardown hook: runs at runtime teardown when this module is linked in
# (binary, or tests that register std/ws). Safe with none live.
onTeardown.add(closeAllWs)

## Builds the std/ws namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn serve(port: int64, hostOrHandlers: JSValueRef,
        handlers ?: JSObjectRef):
      ## ws.serve(port[, host], handlers) -> {port, host}
      if inHttpWorker():
        throwError(ctx,
          "serve: ws.serve is not supported in http worker threads",
          exception)
        return nil
      if port < 1 or port > 65535:
        throwError(ctx, "serve: port must be 1..65535", exception)
        return nil
      let portNum = int(port)
      let n = int(argumentCount)
      var host = "127.0.0.1"
      var handlersObj: JSValueRef = nil
      if n == 2:
        if not objRefCheck(ctx, hostOrHandlers, "serve", "handlers",
            docBlock, exception):
          return nil
        handlersObj = hostOrHandlers
      else:
        var herr = ""
        let h = fromJS(ctx, hostOrHandlers, herr)
        if herr != "" or h.kind != nvkString:
          throwTypeMismatch(ctx, "serve", "host",
            (if herr != "": "unreadable" else: jsTypeName(h.kind)),
            "string", docBlock, exception)
          return nil
        host = h.s
        handlersObj = handlers
      var onOpen, onMessage, onClose, onError: JSObjectRef
      if not readHandlers(ctx, handlersObj, "serve", exception, onOpen,
          onMessage, onClose, onError, docBlock):
        return nil
      let rt = currentRt()
      var wss = newWsServer(rt.ensureLoop())
      let c = ctx
      let r = rt
      let sk = cast[pointer](wss)
      wss.onOpen(proc(ws: WsConnection) {.closure, gcsafe.} =
        {.cast(gcsafe).}:
          if not wsServers.hasKey(sk):
            try:
              ws.closeWs(1000, "")
            except CatchableError:
              discard
            return
          let se = wsServers[sk]
          # Borrowed fns: each accepted conn protects what it references
          # (balanced by its cleanupConn); the server entry keeps its own
          # set for closeAllWs/ws.close.
          if se.onOpen != nil:
            JSValueProtect(c, se.onOpen)
          if se.onMessage != nil:
            JSValueProtect(c, se.onMessage)
          if se.onClose != nil:
            JSValueProtect(c, se.onClose)
          if se.onError != nil:
            JSValueProtect(c, se.onError)
          let handle = makeConnHandle(c, nil)
          if handle == nil:
            # Balances the four protects above; the server keeps its own.
            unprotectHandlers(c, se.onOpen, se.onMessage, se.onClose,
              se.onError)
            try:
              ws.closeWs(1011, "")
            except CatchableError:
              discard
            return
          JSValueProtect(c, handle)
          wsConns[cast[pointer](ws)] = ConnEntry(ctx: c, rt: r, ws: ws,
            handle: handle, onOpen: se.onOpen, onMessage: se.onMessage,
            onClose: se.onClose, onError: se.onError, serverKey: sk,
            closing: false, closed: false, openOk: true, sync: nil)
          # Server-side conns ride the server's pending slot.
          wsOnOpen(ws))
      # Frame/close/error dispatch comes from the server defaults, copied
      # onto each accepted conn at upgrade time. The entry is created in
      # the onOpen closure above, strictly before any of these can fire.
      wss.onMessage(proc(ws: WsConnection; kind: WsFrameKind;
          data: openArray[byte]) {.closure, gcsafe.} =
        {.cast(gcsafe).}:
          wsOnMessage(ws, kind, data))
      wss.onClose(proc(ws: WsConnection; code: int;
          reason: string) {.closure, gcsafe.} =
        {.cast(gcsafe).}:
          wsOnClose(ws, code, reason))
      wss.onError(proc(ws: WsConnection; err: string) {.closure,
          gcsafe.} =
        {.cast(gcsafe).}:
          wsOnError(ws, err))
      try:
        wss.listen(host, portNum)
      except CatchableError as e:
        unprotectHandlers(ctx, onOpen, onMessage, onClose, onError)
        try:
          wss.close()
        except CatchableError:
          discard
        throwError(ctx, "serve: " & e.msg, exception)
        return nil
      wsServers[sk] = ServerEntry(ctx: ctx, rt: rt, server: wss,
        onOpen: onOpen, onMessage: onMessage, onClose: onClose,
        onError: onError, port: portNum, host: host)
      inc rt.pending
      returnJson(ctx, %*{"port": portNum, "host": host}, "serve", exception)

    module.registerFn connect(url: string, handlersObj ?: JSObjectRef):
      ## ws.connect(url[, {headers?, protocols?, timeoutMs?, pingIntervalMs?, idleTimeoutMs?, maxFrameSize?, ...handlers}]) -> Promise<conn>
      var onOpen, onMessage, onClose, onError: JSObjectRef
      if not readHandlers(ctx, handlersObj, "connect", exception, onOpen,
          onMessage, onClose, onError, docBlock):
        return nil
      var copts: WsConnectOpts
      try:
        copts = parseConnectOpts(ctx, handlersObj, "connect")
      except CatchableError as e:
        unprotectHandlers(ctx, onOpen, onMessage, onClose, onError)
        throwError(ctx, e.msg, exception)
        return nil
      var resolveFn, rejectFn: JSObjectRef
      var mkEx: JSValueRef = nil
      let promise = JSObjectMakeDeferredPromise(ctx, addr resolveFn,
        addr rejectFn, addr mkEx)
      if promise == nil or mkEx != nil:
        unprotectHandlers(ctx, onOpen, onMessage, onClose, onError)
        throwError(ctx, "connect: could not create promise", exception)
        return nil
      JSValueProtect(ctx, resolveFn)
      JSValueProtect(ctx, rejectFn)
      let rt = currentRt()
      let handle = startClient(ctx, rt, url, "connect", onOpen, onMessage,
        onClose, onError, resolveFn, rejectFn, nil, copts, exception)
      if handle == nil:
        JSValueUnprotect(ctx, resolveFn)
        JSValueUnprotect(ctx, rejectFn)
        return nil
      promise

    module.registerFn connectSync(url: string, optsObj ?: JSObjectRef):
      ## ws.connectSync(url[, {timeoutMs?, ...}]) -> established conn
      var timeoutMs = DefaultWsTimeoutMs
      var copts = defaultConnectOpts()
      if optsObj != nil:
        try:
          copts = parseConnectOpts(ctx, optsObj, "connectSync")
        except CatchableError as e:
          throwError(ctx, e.msg, exception)
          return nil
        timeoutMs = copts.timeoutMs
      var onOpen, onMessage, onClose, onError: JSObjectRef
      if not readHandlers(ctx, optsObj, "connectSync", exception, onOpen,
          onMessage, onClose, onError, docBlock):
        return nil
      let rt = currentRt()
      let st = SyncState(done: false, ok: false, msg: "")
      let handle = startClient(ctx, rt, url, "connectSync", onOpen,
        onMessage, onClose, onError, nil, nil, st, copts, exception)
      if handle == nil:
        return nil
      let loop = rt.ensureLoop()
      let t0 = getMonoTime()
      while not st.done:
        if rt.exitRequested:
          st.done = true
          st.ok = false
          st.msg = "aborted"
          break
        let elapsed = int(inMilliseconds(getMonoTime() - t0))
        if elapsed >= timeoutMs:
          break
        loop.poll(min(WsSyncSliceMs, timeoutMs - elapsed))
      # Detach: late events must not touch the waiter afterwards.
      let skey = findConnByHandle(handle)
      if skey != nil and wsConns.hasKey(skey):
        var ne = wsConns[skey]
        ne.sync = nil
        wsConns[skey] = ne
      if st.ok:
        return handle
      # Timeout or async failure: failures already released the slot via
      # the dispatchers; on timeout close the conn and release it here.
      var msg = st.msg
      if msg == "":
        msg = "timed out after " & $timeoutMs & "ms"
      let ckey = findConnByHandle(handle)
      if ckey != nil:
        var ne = wsConns[ckey]
        ne.closing = true
        wsConns[ckey] = ne
        if ne.ws != nil and ne.ws.conn != nil:
          try:
            ne.ws.closeWs(1000, "")
          except CatchableError:
            discard
        cleanupConn(ckey)
      throwError(ctx, "connectSync: " & msg, exception)
      nil

    module.registerFn close(port: int64):
      ## ws.close(port) -> bool
      if port < 1 or port > 65535:
        throwError(ctx, "close: port must be 1..65535", exception)
        return nil
      let portNum = int(port)
      var skey: pointer = nil
      var found = false
      for k, se in wsServers.pairs:
        if se.port == portNum:
          skey = k
          found = true
          break
      if not found:
        throwError(ctx, "close: no server on port " & $portNum, exception)
        return nil
      let se = wsServers[skey]
      # Server-side conns die with the listener: drop their entries first
      # so their close events no-op, then close the listener.
      var dead: seq[pointer] = @[]
      for k, e in wsConns.pairs:
        if e.serverKey == skey:
          dead.add(k)
      for k in dead:
        cleanupConn(k)
      unprotectHandlers(se.ctx, se.onOpen, se.onMessage, se.onClose,
        se.onError)
      wsServers.del(skey)
      # The slot is released now; the transport close follows. From inside
      # a user callback it must wait a turn (see queueServerClose).
      decPending(se.rt)
      if wsFireDepth > 0:
        queueServerClose(se.rt, se.server)
        return toJS(ctx, true)
      try:
        se.server.close()
      except CatchableError as err:
        throwError(ctx, "close: " & err.msg, exception)
        return nil
      toJS(ctx, true)
