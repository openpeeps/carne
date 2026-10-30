---
title: XML
description: "XML parsing and serialization."
keywords: ['carne', 'javascript', 'std', 'xml']
---

# XML

XML parsing and serialization. Elements map to `{tag, attrs, children}`. Comments, prologs and doctypes
are dropped on parse.

```js
const xml = require("std/xml");
const node = xml.parse("<note><to>Ada</to></note>");
console.log(node.tag);                          // "note"
console.log(node.children[0].children[0]);      // "Ada" (text nodes are strings)
console.log(xml.stringify(node));
```


## xml.parse

`xml.parse(text) -> {tag, attrs, children}`

```js
const xml = require("std/xml");
xml.parse("example");
```

## xml.stringify

`xml.stringify(node) -> string`

```js
const xml = require("std/xml");
xml.stringify("example");
```
