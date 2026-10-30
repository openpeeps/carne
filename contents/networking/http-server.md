---
title: HTTP Server
description: "Async HTTP server for Carne."
keywords: ['carne', 'javascript', 'std', 'http', 'server']
---

# HTTP Server

Async HTTP server. Handlers return a string, a `{status?, headers?, body?}`
object, or `undefined`; handler throws become 500s.

Built on top of [PowPow](https://github.com/openpeeps/powpow), a
high-performance event notification library for Nim.

## Example

```js
const http = require("std/http");

const srv = http.serve(3000, req => ({body: "hi " + req.path}));
http.close(srv.port);
```

## Request object

Requests carry `{method, path, query, url, headers, body, clientIp}`.

## Handler return values

Handlers return a string, a `{status?, headers?, body?}` object, or
`undefined`. Handler throws become 500s.

## Content-Type defaults

The object form defaults `Content-Type` to `text/plain` for string
bodies and `application/json` for serialized ones unless `headers` sets
one.

## Headers

Header names are lowercased in `req.headers` and `res.headers` (read
them lowercase). Handler-set response headers keep their case on the
wire.

## Empty bodies

HEAD requests and 101/204/205/304 statuses answer with an empty body.

## serve options

`serve(port[, host][, opts], handler)` accepts
`{keepAliveMs?, readTimeoutMs?, maxBodySize?, workers?}`. Client and
server multiplex on one event loop with the timers, truly async.

## Workers

`workers` (1..64, default 1) scales serving across threads. Above 1,
each extra worker is a full runtime (own JS context, loop, server)
re-running the script, sharing the port (a `SO_REUSEPORT` group on
Linux, one adopted listen socket on macOS). JS heaps are isolated per
worker: no shared state, and module-level side effects run once per
worker. Gate driver code on `process.isWorker` (`false` on main,
`true` on workers); `close(port)` stops every worker and process exit
joins them. `ws.serve` is not supported in workers.

```js
const http = require("std/http");
http.serve(3000, {workers: 4}, req => "hello world");
if (!process.isWorker) {
  setTimeout(() => http.close(3000), 1000); // driver: main only
}
```

## http.serve

`http.serve(port[, host][, opts], handler) -> {port, host}`

opts.workers (1..64, default 1) scales across worker threads, each a full runtime re-running the script (see the module header). Workers share the port: Linux balances a REUSEPORT group, macOS adopts one shared listen socket.

```js
const http = require("std/http");
http.serve(3000, {}, {}, "example");
```

## http.close

`http.close(port) -> bool`

```js
const http = require("std/http");
http.close(3000);
```
