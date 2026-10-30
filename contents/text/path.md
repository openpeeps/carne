---
title: Path
description: "File-path and URL parsing."
keywords: ['carne', 'javascript', 'std', 'path', 'url']
---

# Path

file-path and URL parsing. Parse-only in v1. Absent options stay absent.

```js
const path = require("std/path");
console.log(path.parse("/a/b/c.txt").ext); // "txt"
console.log(path.parse("/a/b/c.txt").segments); // ["a", "b", "c.txt"]
const web = path.parse("https://user@host:8080/p?q=1#frag");
console.log(web.host + web.path); // "host/p"
```


## path.parse

`path.parse(text) -> local or network path object`

```js
const path = require("std/path");
path.parse("example");
```
