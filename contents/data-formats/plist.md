---
title: Plist
description: "Apple property lists (XML and binary)."
keywords: ['carne', 'javascript', 'std', 'plist', 'apple']
---

# Plist

```js
const plist = require("std/plist");
const v = plist.parse('<plist version="1.0"><dict><key>Name</key><string>Ada</string></dict></plist>');
console.log(v.Name);          // "Ada" (XML or binary plist in)
console.log(plist.stringify(v)); // XML plist out
```


## plist.parse

`plist.parse(data) -> value (XML or binary plist)`

```js
const plist = require("std/plist");
plist.parse("example");
```

## plist.stringify

`plist.stringify(value) -> string (XML plist)`

```js
const plist = require("std/plist");
plist.stringify("example");
```
