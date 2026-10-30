# Carne std/http: async HTTP client + server via powpow.
#
#   const http = require("std/http");
#   await http.fetch("https://example.com/")
#     -> {status: 200, statusText: "OK", headers: {...}, body: "..."}
#   await http.get(url[, {headers, timeoutMs}])
#   await http.post(url, body[, {headers, timeoutMs}])
#   await http.put(url, body[, opts]) // patch, delete, head, options too
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
# HEAD requests and 101/204/205/304 statuses answer with an empty body
# (fetch null-body-status semantics). The request object carries
# {method, path, query, url, headers, body, clientIp}.
# serve takes tuning opts: serve(port[, host][, opts], handler) with
# opts = {keepAliveMs?, readTimeoutMs?, maxBodySize?}.
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
import ../modules

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

proc parseOpts(ctx: JSContextRef; obj: JSValueRef; name: string;
    allowMethod, allowBody: bool): FetchOpts =
  ## Reads {method?, headers?, body?, timeoutMs?} lazily; absent and
  ## undefined fields both mean default. Raises on anything else
  ## (callers turn it into a sync JS throw). nil obj means absent.
  result = FetchOpts(meth: HttpGet, headers: @[], body: "", timeoutMs: -1)
  if obj == nil:
    return
  var err = ""
  template field(key: string): NimValue =
    let f = getField(ctx, obj, key, err)
    if err != "":
      raise newException(CatchableError, name & ": options." & key & " " & err)
    f
  let m = field("method")
  if m.kind != nvkUndefined:
    if not allowMethod:
      raise newException(CatchableError,
        name & ": method is fixed here, use fetch for full control")
    if m.kind != nvkString:
      raise newException(CatchableError,
        name & ": options.method must be a string")
    result.meth = methodFromString(m.s, name)
  let b = field("body")
  if b.kind != nvkUndefined:
    if not allowBody:
      raise newException(CatchableError,
        name & ": body is fixed here, use fetch for full control")
    if b.kind != nvkString:
      raise newException(CatchableError,
        name & ": options.body must be a string")
    result.body = b.s
  let h = field("headers")
  if h.kind != nvkUndefined:
    if h.kind != nvkObject:
      raise newException(CatchableError,
        name & ": options.headers must be an object")
    for k, hv in h.obj.pairs:
      if hv.kind != nvkString:
        raise newException(CatchableError,
          name & ": header \"" & k & "\" must be a string")
      result.headers.add((k, hv.s))
  let t = field("timeoutMs")
  if t.kind != nvkUndefined:
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

proc reqToJson(req: HttpRequest; clientIp: string): JsonNode =
  result = newJObject()
  result["method"] = %methodToString(req.getMethod())
  let p: string = req.getPath()
  let q: string = req.getQuery()
  let u: string = req.getUrl()
  result["path"] = %p
  result["query"] = %q
  result["url"] = %u
  result["clientIp"] = %clientIp
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
    let headOnly = req.getMethod() == HttpHead
    var clientIp = ""
    try:
      clientIp = res.getClientIp()
    except CatchableError:
      clientIp = ""
    let reqVal = jsonToJS(c, reqToJson(req, clientIp))
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
        .send(if headOnly: "" else: valueToString(c, ret))
      return
    var jerr = ""
    let node = jsToJson(c, ret, jerr)
    if node == nil:
      res.sendError(Http500, "handler returned non-serializable value")
      return
    if node.kind != JObject:
      res.status(Http200).header("Content-Type", "application/json")
        .send(if headOnly: "" else: $node)
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
    # Null-body statuses (fetch semantics) and HEAD never carry a body.
    if headOnly or code in {Http101, Http204, Http205, Http304}:
      body = ""
    res.status(code)
    for (k, v) in hdrs:
      res.header(k, v)
    res.send(body)

proc serveOptNum(ctx: JSContextRef; obj: JSValueRef; name, key: string;
    allowZero: bool): int =
  ## One numeric serve opt, -1 when absent/undefined. Raises on anything
  ## malformed (callers turn it into a sync JS throw).
  var err = ""
  let f = getField(ctx, obj, key, err)
  if err != "":
    raise newException(CatchableError, name & ": opts." & key & " " & err)
  if f.kind == nvkUndefined:
    return -1
  var v = -1
  case f.kind
  of nvkInt: v = int(f.i)
  of nvkFloat: v = int(f.f)
  else:
    raise newException(CatchableError,
      name & ": opts." & key & " must be a number")
  if v < 0 or (v == 0 and not allowZero):
    raise newException(CatchableError, name & ": opts." & key &
      (if allowZero: " must be >= 0" else: " must be positive"))
  v

proc parseServeOpts(ctx: JSContextRef; obj: JSValueRef; name: string):
    HttpServerOptions =
  ## Reads {keepAliveMs?, readTimeoutMs?, maxBodySize?} from the serve
  ## opts object, starting from powpow's defaults. Raises on anything
  ## malformed (callers turn it into a sync JS throw).
  result = defaultHttpServerOptions()
  let ka = serveOptNum(ctx, obj, name, "keepAliveMs", true)
  if ka >= 0:
    result.keepAliveMs = ka
  let rt = serveOptNum(ctx, obj, name, "readTimeoutMs", true)
  if rt >= 0:
    result.readTimeoutMs = rt
  let mb = serveOptNum(ctx, obj, name, "maxBodySize", false)
  if mb >= 0:
    result.maxBodySize = mb

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

# Teardown hook: runs at runtime teardown when this module is linked in
# (binary, or tests that register std/http). Safe with none live.
onTeardown.add(closeAllServers)

## Builds the std/http namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn fetch(url: string, optsObj ?: JSObjectRef):
      ## http.fetch(url[, {method, headers, body, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      var opts: FetchOpts
      try:
        opts = parseOpts(ctx, optsObj, "fetch", true, true)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      startFetch(ctx, currentRt(), url, opts, "fetch", exception)

    module.registerFn get(url: string, optsObj ?: JSObjectRef):
      ## http.get(url[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      var opts: FetchOpts
      try:
        opts = parseOpts(ctx, optsObj, "get", false, false)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      startFetch(ctx, currentRt(), url, opts, "get", exception)

    module.registerFn post(url: string, body: string,
        optsObj ?: JSObjectRef):
      ## http.post(url, body[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      var opts: FetchOpts
      try:
        opts = parseOpts(ctx, optsObj, "post", false, false)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      opts.meth = HttpPost
      opts.body = body
      startFetch(ctx, currentRt(), url, opts, "post", exception)

    module.registerFn put(url: string, body: string,
        optsObj ?: JSObjectRef):
      ## http.put(url, body[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      var opts: FetchOpts
      try:
        opts = parseOpts(ctx, optsObj, "put", false, false)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      opts.meth = HttpPut
      opts.body = body
      startFetch(ctx, currentRt(), url, opts, "put", exception)

    module.registerFn patch(url: string, body: string,
        optsObj ?: JSObjectRef):
      ## http.patch(url, body[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      var opts: FetchOpts
      try:
        opts = parseOpts(ctx, optsObj, "patch", false, false)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      opts.meth = HttpPatch
      opts.body = body
      startFetch(ctx, currentRt(), url, opts, "patch", exception)

    module.registerFn delete(url: string, optsObj ?: JSObjectRef):
      ## http.delete(url[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      var opts: FetchOpts
      try:
        opts = parseOpts(ctx, optsObj, "delete", false, false)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      opts.meth = HttpDelete
      startFetch(ctx, currentRt(), url, opts, "delete", exception)

    module.registerFn head(url: string, optsObj ?: JSObjectRef):
      ## http.head(url[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}> (body is always "")
      var opts: FetchOpts
      try:
        opts = parseOpts(ctx, optsObj, "head", false, false)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      opts.meth = HttpHead
      startFetch(ctx, currentRt(), url, opts, "head", exception)

    module.registerFn options(url: string, optsObj ?: JSObjectRef):
      ## http.options(url[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>
      var opts: FetchOpts
      try:
        opts = parseOpts(ctx, optsObj, "options", false, false)
      except CatchableError as e:
        throwError(ctx, e.msg, exception)
        return nil
      opts.meth = HttpOptions
      startFetch(ctx, currentRt(), url, opts, "options", exception)

    module.registerFn serve(port: int64, second: JSValueRef,
        third ?: JSValueRef, handler ?: JSObjectRef):
      ## http.serve(port[, host][, opts], handler) -> {port, host}
      if port < 1 or port > 65535:
        throwError(ctx, "serve: port must be 1..65535", exception)
        return nil
      let portNum = int(port)
      let n = int(argumentCount)
      var host = "127.0.0.1"
      var haveOpts = false
      var sopts = defaultHttpServerOptions()
      var handlerV: JSValueRef = nil
      if n == 2:
        var ferr2 = ""
        let hv2 = fromJS(ctx, second, ferr2)
        if ferr2 != "" or hv2.kind != nvkFunction:
          throwTypeMismatch(ctx, "serve", "handler",
            (if ferr2 != "": "unreadable" else: jsTypeName(hv2.kind)),
            "function", docBlock, exception)
          return nil
        handlerV = second
      elif n == 3:
        var serr = ""
        let sk = fromJS(ctx, second, serr)
        if serr == "" and sk.kind == nvkString:
          host = sk.s
        elif serr == "" and sk.kind == nvkObject:
          try:
            sopts = parseServeOpts(ctx, second, "serve")
          except CatchableError as e:
            throwError(ctx, e.msg, exception)
            return nil
          haveOpts = true
        else:
          throwTypeMismatch(ctx, "serve", "hostOrOpts",
            (if serr != "": "unreadable" else: jsTypeName(sk.kind)),
            "string|object", docBlock, exception)
          return nil
        var ferr3 = ""
        let hv3 = fromJS(ctx, third, ferr3)
        if ferr3 != "" or hv3.kind != nvkFunction:
          throwTypeMismatch(ctx, "serve", "handler",
            (if ferr3 != "": "unreadable" else: jsTypeName(hv3.kind)),
            "function", docBlock, exception)
          return nil
        handlerV = third
      else:
        var herr = ""
        let h = fromJS(ctx, second, herr)
        if herr != "" or h.kind != nvkString:
          throwTypeMismatch(ctx, "serve", "host",
            (if herr != "": "unreadable" else: jsTypeName(h.kind)),
            "string", docBlock, exception)
          return nil
        host = h.s
        var oerr = ""
        let oo = fromJS(ctx, third, oerr)
        if oerr != "" or oo.kind != nvkObject:
          throwTypeMismatch(ctx, "serve", "opts",
            (if oerr != "": "unreadable" else: jsTypeName(oo.kind)),
            "object", docBlock, exception)
          return nil
        try:
          sopts = parseServeOpts(ctx, third, "serve")
        except CatchableError as e:
          throwError(ctx, e.msg, exception)
          return nil
        haveOpts = true
        var ferr4 = ""
        let hv4 = fromJS(ctx, handler, ferr4)
        if ferr4 != "" or hv4.kind != nvkFunction:
          throwTypeMismatch(ctx, "serve", "handler",
            (if ferr4 != "": "unreadable" else: jsTypeName(hv4.kind)),
            "function", docBlock, exception)
          return nil
        handlerV = handler
      let rt = currentRt()
      var server = newHttpServer(rt.ensureLoop(), populate = false)
      if haveOpts:
        server.applyOptions(sopts)
      server.handler = httpOnRequest
      try:
        server.listen(host, portNum)
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
          port: portNum, host: host)
      returnJson(ctx, %*{"port": portNum, "host": host}, "serve", exception)

    module.registerFn close(port: int64):
      ## http.close(port) -> bool
      if port < 1 or port > 65535:
        throwError(ctx, "close: port must be 1..65535", exception)
        return nil
      let portNum = int(port)
      var target: ServerEntry
      var found = false
      for k, e in httpServers.pairs:
        if e.port == portNum:
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
