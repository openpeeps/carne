---
title: WebSocket
description: "Async and sync WebSocket client and server."
keywords: ['carne', 'javascript', 'std', 'ws', 'websocket']
---

# WebSocket

Async + sync WebSocket client and server, example:

```js
const ws = require("std/ws");

// Server (stays alive until closed, like Node)
const srv = ws.serve(8080, {
  onMessage: (conn, msg) => conn.send("hi " + msg.data)
});

// Async client (handshake on the loop; wrap in an async IIFE)
(async () => {
  const c = await ws.connect("ws://127.0.0.1:8080/chat", {
    onMessage: (msg) => {
      console.log(msg.data); // hi ada
      c.close();
      ws.close(srv.port);
    }
  });
  c.send("ada");
})();

// Sync client (blocks until open)
const c2 = ws.connectSync("ws://127.0.0.1:8080/chat");
c2.send("sync");
c2.close();
```

## connect

`connect(url[, opts])` returns a Promise for the
`{send, ping, protocol, close}` handle (`await ws.connect(...)` or
`.then(...)`).

## connectSync

`connectSync(url[, opts])` pumps the same loop until open (default 10s).

## Options

`opts` carries `{headers?, protocols?, timeoutMs?, pingIntervalMs?,
idleTimeoutMs?, maxFrameSize?}` alongside the handlers.

## send

`send(text[, {binary}])` delivers binary frames as strings with
`isBinary: true`.

## ping

`ping([data])` sends a control ping.

## protocol

`protocol()` returns the negotiated subprotocol (`""` when none).

## Callbacks

Server callbacks get `(conn, payload)`, client callbacks just
`(payload)`. Messages are `{data, isBinary}`, closes `{code, reason}`,
errors `{message}`. Handshake failures reject the promise (an `onError`
handler fires too when given).

## TLS

`wss://` clients use a shared TLS context with system CAs; serving
`wss://` needs cert loading and is out of scope in v1.


## conn.send

`conn.send(text[, {binary}]): thisObject is the handle created by connect/serve.`

```js
const ws = require("std/ws");
conn.send("example", {});
```

## conn.close

`conn.close([code[, reason]]): final, idempotent; the pending slot is`

released when the close lands (or at teardown).

```js
const ws = require("std/ws");
conn.close(1000, "example");
```

## conn.ping

`conn.ping([data]): send a control ping; the peer's pong is answered internally.`

```js
const ws = require("std/ws");
conn.ping("example");
```

## conn.protocol

`conn.protocol(): the subprotocol the server selected ("" when none).`

```js
const ws = require("std/ws");
conn.protocol();
```

## ws.serve

`ws.serve(port[, host], handlers) -> {port, host}`

```js
const ws = require("std/ws");
ws.serve(3000, "example", {});
```

## ws.connect

`ws.connect(url[, {headers?, protocols?, timeoutMs?, pingIntervalMs?, idleTimeoutMs?, maxFrameSize?, ...handlers}]) -> Promise<conn>`

```js
const ws = require("std/ws");
ws.connect("https://example.com/", {});
```

## ws.connectSync

`ws.connectSync(url[, {timeoutMs?, ...}]) -> established conn`

```js
const ws = require("std/ws");
ws.connectSync("https://example.com/", {});
```

## ws.close

`ws.close(port) -> bool`

```js
const ws = require("std/ws");
ws.close(3000);
```
