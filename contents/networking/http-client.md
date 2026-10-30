---
title: HTTP Client
description: "Async HTTP client for Carne."
keywords: ['carne', 'javascript', 'std', 'http', 'client']
---

# HTTP Client

The HTTP client is fully async and Promise-based. All client methods
return a Promise that resolves to `{status, statusText, headers, body}`.

Built on top of [PowPow](https://github.com/openpeeps/powpow), a
high-performance event notification library for Nim.

## Example

```js
const http = require("std/http");

(async () => {
  const res = await http.get("https://example.com/");
  console.log(res.status, res.body.length);
  const posted = await http.post("https://example.com/api", "hi");
  const custom = await http.fetch("https://example.com/", {method: "PUT", body: "x"});
})();
```

## HTTP Client

The HTTP client is fully async and Promise-based. All client methods
return a Promise that resolves to `{status, statusText, headers, body}`.

## Client methods

- `fetch(url[, {method, headers, body, timeoutMs}])` returns
  `{status, statusText, headers, body}`.
- `get`/`delete`/`head`/`options` take `(url[, opts])`.
- `post`/`put`/`patch` take `(url, body[, opts])`.

## http.fetch

`http.fetch(url[, {method, headers, body, timeoutMs}]) -> Promise<{status, statusText, headers, body}>`

```js
const http = require("std/http");
http.fetch("https://example.com/", {});
```

## http.get

`http.get(url[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>`

```js
const http = require("std/http");
http.get("https://example.com/", {});
```

## http.post

`http.post(url, body[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>`

```js
const http = require("std/http");
http.post("https://example.com/", "example", {});
```

## http.put

`http.put(url, body[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>`

```js
const http = require("std/http");
http.put("https://example.com/", "example", {});
```

## http.patch

`http.patch(url, body[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>`

```js
const http = require("std/http");
http.patch("https://example.com/", "example", {});
```

## http.delete

`http.delete(url[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>`

```js
const http = require("std/http");
http.delete("https://example.com/", {});
```

## http.head

`http.head(url[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}> (body is always "")`

```js
const http = require("std/http");
http.head("https://example.com/", {});
```

## http.options

`http.options(url[, {headers, timeoutMs}]) -> Promise<{status, statusText, headers, body}>`

```js
const http = require("std/http");
http.options("https://example.com/", {});
```
