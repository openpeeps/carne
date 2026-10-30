---
title: Mimetype
description: "MIME type lookup."
keywords: ['carne', 'javascript', 'std', 'mimetype', 'mime']
---

# Mimetype

MIME type lookup over the `mimedb` database (bundled, parsed lazily on first query).
Extensions accept a leading dot and any case; unknown inputs answer `null`.
`info` returns `{source, extensions, compressible}`.

```js
const mimetype = require("std/mimetype");
console.log(mimetype.lookup(".PNG")); // "image/png"
console.log(mimetype.lookup("nope")); // null
console.log(JSON.stringify(mimetype.info("text/html").extensions)); // ["html","htm","shtml"]
console.log(mimetype.isExtension("zip"), mimetype.has("audio/mp4")); // true true
```


## mimetype.lookup

`mimetype.lookup(ext) -> MIME type string or null`

```js
const mimetype = require("std/mimetype");
mimetype.lookup("example");
```

## mimetype.info

`mimetype.info(type) -> {source, extensions, compressible} or null`

```js
const mimetype = require("std/mimetype");
mimetype.info("example");
```

## mimetype.isExtension

`mimetype.isExtension(ext) -> bool`

```js
const mimetype = require("std/mimetype");
mimetype.isExtension("example");
```

## mimetype.has

`mimetype.has(type) -> bool`

```js
const mimetype = require("std/mimetype");
mimetype.has("example");
```
