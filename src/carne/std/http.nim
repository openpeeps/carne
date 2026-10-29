# Carne std/http: async HTTP client + server via powpow.
#
#   const http = require("std/http");
#   await http.fetch("https://example.com/")
#     -> {status: 200, statusText: "OK", headers: {...}, body: "..."}
#   await http.get(url[, {headers, timeoutMs}])
#   await http.post(url, body[, {headers, timeoutMs}])
#   const srv = http.serve(3000, req => ({body: "hi " + req.path}));
#   http.close(srv.port)
#
# fetch/get/post return Promises multiplexed on the run's shared powpow
# loop together with timers and serve sockets: truly async, no threads.
# serve borrows the loop and holds it alive until close (Node semantics).
# Handler return: string -> 200 text/plain; {status?, headers?, body?};
# undefined/null -> 200 empty; anything else -> JSON body. A JS throw in
# a handler answers 500 and is recorded as uncaught. Bodies are UTF-8
# strings in v1; https uses a default client context with system CAs.
#
# Note: scripts need an async IIFE for await (top-level await is out of
# scope in v1): `(async () => { ... })()`. The runtime unwraps a
# top-level completion promise, so tests assert on it directly.

import std/[json, strutils, tables]
import std/httpcore except HttpMethod

import javascriptcore

import powpow/types
import powpow/proto/http
import powpow/proto/httpclient
import powpow/proto/httpserver
from powpow/loop import stop
from powpow/net/tls import SslContext, newClientTlsContext

import ../bridge

type
  FetchOpts = object
    meth: HttpMethod
    headers: seq[(string, string)]
    body: string
    timeoutMs: int

  ServerEntry = object
    ctx: JSContextRef
    rt: Runtime
    server: HttpServer
    handlerFn: JSObjectRef
    port: int
    host: string

var httpServers: Table[pointer, ServerEntry]
var httpClients: Table[pointer, HttpClientBase]

proc decPending(rt: Runtime) =
  dec rt.pending
  if rt.pending <= 0 and not rt.exitRequested:
    rt.pending = 0
    rt.loop.stop()

proc methodFromString(s: string; name: string): HttpMethod =
  case s.toUpperAscii()
  of "GET": HttpGet
  of "POST": HttpPost
  of "PUT": HttpPut
  of "DELETE": HttpDelete
  of "HEAD": HttpHead
  of "OPTIONS": HttpOptions
  of "PATCH": HttpPatch
  else:
    raise newException(CatchableError, name & ": unknown method \"" & s & "\"")

proc methodToString(m: HttpMethod): string =
  case m
  of HttpGet: "GET"
  of HttpPost: "POST"
  of HttpPut: "PUT"
  of HttpDelete: "DELETE"
  of HttpHead: "HEAD"
  of HttpOptions: "OPTIONS"
  of HttpPatch: "PATCH"
  else: ($m)[4 .. ^1].toUpperAscii()

proc parseOpts(v: NimValue; name: string; allowMethod,
    allowBody: bool): FetchOpts =
  ## Reads {method?, headers?, body?, timeoutMs?}. Raises on anything
  ## else (callers turn it into a sync JS throw).
  result = FetchOpts(meth: HttpGet, headers: @[], body: "", timeoutMs: -1)
  if v.kind == nvkUndefined:
    return
  if v.kind != nvkObject:
    raise newException(CatchableError, name & ": options must be an object")
  if v.hasKey("method"):
    if not allowMethod:
      raise newException(CatchableError,
        name & ": method is fixed here, use fetch for full control")
    let m = v.get("method", name)
    if m.kind != nvkString:
      raise newException(CatchableError,
        name & ": options.method must be a string")
    result.meth = methodFromString(m.s, name)
  if v.hasKey("body"):
    if not allowBody:
      raise newException(CatchableError,
        name & ": body is fixed here, use fetch for full control")
    let b = v.get("body", name)
    if b.kind != nvkString:
      raise newException(CatchableError,
        name & ": options.body must be a string")
    result.body = b.s
  if v.hasKey("headers"):
    let h = v.get("headers", name)
    if h.kind != nvkObject:
      raise newException(CatchableError,
        name & ": options.headers must be an object")
    for k, hv in h.obj.pairs:
      if hv.kind != nvkString:
        raise newException(CatchableError,
          name & ": header \"" & k & "\" must be a string")
      result.headers.add((k, hv.s))
  if v.hasKey("timeoutMs"):
    let t = v.get("timeoutMs", name)
    case t.kind
    of nvkInt: result.timeoutMs = int(t.i)
    of nvkFloat: result.timeoutMs = int(t.f)
    else:
      raise newException(CatchableError,
        name & ": options.timeoutMs must be a number")

proc clientFor(rt: Runtime; needTls: bool): HttpClientBase =
  ## One shared client (pool + TLS context) per run. Freed by
  ## closeAllServers in the runtime teardown. The TLS context is only
  ## created for https URLs: plain-http runs never pay OpenSSL init.
  let key = cast[pointer](rt)
  if httpClients.hasKey(key):
    result = httpClients[key]
    if needTls and result.tlsCtx == nil:
      try:
        result.tlsCtx = newClientTlsContext()
      except CatchableError:
        discard
    return result
  var tlsCtx: SslContext = nil
  if needTls:
    try:
      tlsCtx = newClientTlsContext()
    except CatchableError:
      tlsCtx = nil
  result = HttpClientBase(tlsCtx: tlsCtx, keepAlive: true, timeoutMs: 0,
    maxBodySize: DefaultMaxResponseBody, defaultHeaders: @[],
    pool: newHttpConnPool())
  httpClients[key] = result

proc responseToJson(res: HttpClientResponse): JsonNode =
  # Everything is copied out here: with keepAlive the parser is reused
  # by the next request on a pooled connection.
  result = newJObject()
  result["status"] = %int(res.getStatusCode())
  let st: string = res.getStatusText()
  result["statusText"] = %st
  var hdrs = newJObject()
  for k, v in res.getHeaders().pairs:
    hdrs[k] = %v
  result["headers"] = hdrs
  result["body"] = %res.getBodyString()

proc reqToJson(req: HttpRequest): JsonNode =
  result = newJObject()
  result["method"] = %methodToString(req.getMethod())
  let p: string = req.getPath()
  let q: string = req.getQuery()
  let u: string = req.getUrl()
  result["path"] = %p
  result["query"] = %q
  result["url"] = %u
  var hdrs = newJObject()
  for k, v in req.getHeaders().pairs:
    hdrs[k] = %v
  result["headers"] = hdrs
  result["body"] = %req.getBodyString()

proc startFetch(ctx: JSContextRef; rt: Runtime; url: string; opts: FetchOpts;
    name: string; exception: ptr JSValueRef): JSValueRef =
  ## Issues one async request on the run's loop and returns its Promise.
  ## Sync setup failures throw; network failures reject. Top-level helper
  ## (not a member body): the settle closures below capture only locals,
  ## never callback bindings.
  var resolveFn, rejectFn: JSObjectRef
  var mkEx: JSValueRef = nil
  let promise =
    JSObjectMakeDeferredPromise(ctx, addr resolveFn, addr rejectFn, addr mkEx)
  if promise == nil or mkEx != nil:
    throwError(ctx, name & ": could not create promise", exception)
    return nil
  JSValueProtect(ctx, promise)
  JSValueProtect(ctx, resolveFn)
  JSValueProtect(ctx, rejectFn)
  inc rt.pending
  let c = ctx
  var done = false
  proc finish() =
    JSValueUnprotect(c, promise)
    JSValueUnprotect(c, resolveFn)
    JSValueUnprotect(c, rejectFn)
    decPending(rt)
  proc rejectWith(msg: string) =
    try:
      let msgV = toJS(c, name & ": " & msg)
      var e2: JSValueRef = nil
      let errObj = JSObjectMakeError(c, 1, unsafeAddr msgV, addr e2)
      var arg = if errObj != nil: errObj else: msgV
      discard JSObjectCallAsFunction(c, rejectFn, nil, 1, addr arg, addr e2)
    except CatchableError:
      discard
    finish()
  proc settleOk(res: HttpClientResponse) {.closure.} =
    if done:
      return
    done = true
    try:
      let v = jsonToJS(c, responseToJson(res))
      if v == nil:
        rejectWith("could not convert response to JS")
        return
      var e2: JSValueRef = nil
      var vv = v
      discard JSObjectCallAsFunction(c, resolveFn, nil, 1, addr vv, addr e2)
    except CatchableError as e:
      rejectWith(e.msg)
      return
    finish()
  proc settleErr(msg: string) {.closure.} =
    if done:
      return
    done = true
    rejectWith(msg)
  let cMeth = opts.meth
  let cHeaders = opts.headers
  let cTimeout = opts.timeoutMs
  let cBody = opts.body
  try:
    let needTls = url.strip().toLowerAscii().startsWith("https:")
    let client = clientFor(rt, needTls)
    let loop = rt.ensureLoop()
    if cBody.len > 0:
      discard requestImpl(client, loop, cMeth, url,
        cBody.toOpenArrayByte(0, cBody.high), cHeaders, "", cTimeout,
        onResponse = settleOk, onBodyData = nil, onError = settleErr)
    else:
      discard requestImpl(client, loop, cMeth, url,
        [], cHeaders, "", cTimeout,
        onResponse = settleOk, onBodyData = nil, onError = settleErr)
  except CatchableError as e:
    finish()
    throwError(ctx, name & ": " & e.msg, exception)
    return nil
  promise

proc httpOnRequest(req: HttpRequest; res: HttpResponse) {.gcsafe.} =
  ## powpow dispatch: runs on the loop thread, which is the JS thread
  ## (borrowed loop), so JS calls are sound; the cast covers the global
  ## table, which no other thread touches.
  {.cast(gcsafe).}:
    let srvKey = cast[pointer](res.server)
    if not httpServers.hasKey(srvKey):
      res.sendError(Http500, "server closed")
      return
    let e = httpServers[srvKey]
    let c = e.ctx
    let reqVal = jsonToJS(c, reqToJson(req))
    var ex: JSValueRef = nil
    var argv: array[1, JSValueRef]
    argv[0] = reqVal
    let ret = JSObjectCallAsFunction(c, e.handlerFn, nil, 1, addr argv[0],
      addr ex)
    if ex != nil or ret == nil:
      if e.rt.uncaught.len == 0:
        e.rt.uncaught =
          if ex != nil: valueToString(c, ex) else: "handler failed"
        e.rt.exitCode = 1
      res.sendError(Http500, "handler threw")
      return
    if JSValueIsUndefined(c, ret) or JSValueIsNull(c, ret):
      res.status(Http200).send("")
      return
    if JSValueIsString(c, ret):
      res.status(Http200)
        .header("Content-Type", "text/plain; charset=utf-8")
        .send(valueToString(c, ret))
      return
    var jerr = ""
    let node = jsToJson(c, ret, jerr)
    if node == nil:
      res.sendError(Http500, "handler returned non-serializable value")
      return
    if node.kind != JObject:
      res.status(Http200).header("Content-Type", "application/json")
        .send($node)
      return
    var code = Http200
    if node.hasKey("status"):
      let s = node["status"]
      if s.kind != JInt or s.getInt() < 100 or s.getInt() > 599:
        res.sendError(Http500, "handler status must be 100..599")
        return
      code = HttpCode(int(s.getInt()))
    var hdrs: seq[(string, string)] = @[]
    if node.hasKey("headers"):
      let h = node["headers"]
      if h.kind != JObject:
        res.sendError(Http500, "handler headers must be an object")
        return
      for k, v in h.pairs:
        if v.kind != JString:
          res.sendError(Http500, "handler header values must be strings")
          return
        hdrs.add((k, v.getStr()))
    var body = ""
    if node.hasKey("body"):
      let b = node["body"]
      if b.kind == JString:
        body = b.getStr()
      elif b.kind == JNull:
        body = ""
      else:
        body = $b
    res.status(code)
    for (k, v) in hdrs:
      res.header(k, v)
    res.send(body)

proc closeServerEntry(srv: HttpServer; e: ServerEntry) =
  srv.close()
  JSValueUnprotect(e.ctx, e.handlerFn)
  httpServers.del(cast[pointer](srv))
  decPending(e.rt)

proc closeAllServers*() =
  ## Closes every live server and frees per-run client pools. Called
  ## from the runtime teardown; safe with none live.
  var keys: seq[pointer] = @[]
  for k in httpServers.keys:
    keys.add(k)
  for k in keys:
    let e = httpServers[k]
    try:
      closeServerEntry(e.server, e)
    except CatchableError:
      discard
  var rts: seq[pointer] = @[]
  for k in httpClients.keys:
    rts.add(k)
  for k in rts:
    try:
      httpClients[k].pool.closeAll()
    except CatchableError:
      discard
    httpClients.del(k)

## Builds the std/http namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn fetch:
      ## http.fetch(url[, {method, headers, body, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      if not checkArity(argumentCount, 1, 2, "fetch", ctx, exception):
        return nil
      var url: string
      if not strArg(ctx, args, 0, "fetch", exception, url):
        return nil
      var optsVal = NimValue(kind: nvkUndefined)
      if int(argumentCount) == 2:
        if not nimArg(ctx, args, 1, "fetch", exception, optsVal):
          return nil
      var opts: FetchOpts
      try:
        opts = parseOpts(optsVal, "fetch", true, true)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      startFetch(ctx, currentRt(), url, opts, "fetch", exception)

    module.registerFn get:
      ## http.get(url[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      if not checkArity(argumentCount, 1, 2, "get", ctx, exception):
        return nil
      var url: string
      if not strArg(ctx, args, 0, "get", exception, url):
        return nil
      var optsVal = NimValue(kind: nvkUndefined)
      if int(argumentCount) == 2:
        if not nimArg(ctx, args, 1, "get", exception, optsVal):
          return nil
      var opts: FetchOpts
      try:
        opts = parseOpts(optsVal, "get", false, false)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      startFetch(ctx, currentRt(), url, opts, "get", exception)

    module.registerFn post:
      ## http.post(url, body[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      if not checkArity(argumentCount, 2, 3, "post", ctx, exception):
        return nil
      var url, body: string
      if not strArg(ctx, args, 0, "post", exception, url):
        return nil
      if not strArg(ctx, args, 1, "post", exception, body):
        return nil
      var optsVal = NimValue(kind: nvkUndefined)
      if int(argumentCount) == 3:
        if not nimArg(ctx, args, 2, "post", exception, optsVal):
          return nil
      var opts: FetchOpts
      try:
        opts = parseOpts(optsVal, "post", false, false)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      opts.meth = HttpPost
      opts.body = body
      startFetch(ctx, currentRt(), url, opts, "post", exception)

    module.registerFn serve:
      ## http.serve(port[, host], handler) -> {port, host}
      if not checkArity(argumentCount, 2, 3, "serve", ctx, exception):
        return nil
      var portF = 0.0
      if not numArg(ctx, args, 0, "serve", exception, portF):
        return nil
      if portF != portF or int(portF) < 1 or int(portF) > 65535:
        throwError(ctx, "serve: port must be 1..65535", exception)
        return nil
      let port = int(portF)
      var host = "127.0.0.1"
      var handlerIdx = 1
      if int(argumentCount) == 2:
        handlerIdx = 1
      else:
        if not strArg(ctx, args, 1, "serve", exception, host):
          return nil
        handlerIdx = 2
      var handlerVal: NimValue
      if not nimArg(ctx, args, handlerIdx, "serve", exception, handlerVal):
        return nil
      if handlerVal.kind != nvkFunction:
        throwError(ctx, "serve: handler is not a function, got " &
          jsTypeName(handlerVal.kind), exception)
        return nil
      let handlerV = handlerVal.raw
      let rt = currentRt()
      var server = newHttpServer(rt.ensureLoop(), populate = false)
      server.handler = httpOnRequest
      try:
        server.listen(host, port)
      except CatchableError as e:
        try:
          server.close()
        except CatchableError:
          discard
        throwError(ctx, "serve: " & e.msg, exception)
        return nil
      JSValueProtect(ctx, handlerV)
      inc rt.pending
      httpServers[cast[pointer](server)] =
        ServerEntry(ctx: ctx, rt: rt, server: server, handlerFn: handlerV,
          port: port, host: host)
      returnJson(ctx, %*{"port": port, "host": host}, "serve", exception)

    module.registerFn close:
      ## http.close(port) -> bool
      if not checkArity(argumentCount, 1, 1, "close", ctx, exception):
        return nil
      var portF = 0.0
      if not numArg(ctx, args, 0, "close", exception, portF):
        return nil
      if portF != portF or int(portF) < 1 or int(portF) > 65535:
        throwError(ctx, "close: port must be 1..65535", exception)
        return nil
      let port = int(portF)
      var target: ServerEntry
      var found = false
      for k, e in httpServers.pairs:
        if e.port == port:
          target = e
          found = true
          break
      if not found:
        throwError(ctx, "close: no server on port " & $port, exception)
        return nil
      try:
        closeServerEntry(target.server, target)
      except CatchableError as err:
        throwError(ctx, "close: " & err.msg, exception)
        return nil
      toJS(ctx, true)
