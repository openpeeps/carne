---
title: SVG
description: "SVG parsing."
keywords: ['carne', 'javascript', 'std', 'svg']
---

# SVG

SVG parsing. Elements map to `{tag, attrs, children}` (same shape as `std/xml`);
text, comments and CDATA become `{kind, text}` leaves. Serialization
is out of scope in v1, pair with `std/xml` when you need to write SVG.

```js
const svg = require("std/svg");
const node = svg.parse('<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>');
console.log(node.tag);              // "svg"
console.log(node.children.length);  // 1
```


## svg.parse

`svg.parse(text) -> {tag, attrs, children}`

```js
const svg = require("std/svg");
svg.parse("example");
```
