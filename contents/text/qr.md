---
title: QR
description: "QR code generation."
keywords: ['carne', 'javascript', 'std', 'qr']
---

# QR

QR code generation (Model 2). Decoding is out of scope in v1.

```js
const qr = require("std/qr");
const code = qr.encode("hello"); // {size, svg, terminal}
console.log(code.size);          // 21
console.log(code.svg.slice(0, 5)); // "<svg "
qr.encode("hello", {ecLevel: "H"}); // higher error correction (L/M/Q/H)
```


## qr.encode

`qr.encode(text[, {ecLevel}]) -> {size, svg, terminal}`

```js
const qr = require("std/qr");
qr.encode("example", {});
```
