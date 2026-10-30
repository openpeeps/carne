---
title: BSON
description: "BSON parsing and serialization."
keywords: ['carne', 'javascript', 'std', 'bson']
---

# BSON

BSON parsing and serialization. Raw BSON bytes travel with an opaque mapping (do not read the string
as text); `stringify` output always parses back.

```js
const bson = require("std/bson");
const blob = bson.stringify({name: "ada", n: 1});
console.log(JSON.stringify(bson.parse(blob))); // {"name":"ada","n":1}
```


## bson.parse

`bson.parse(data) -> value`

```js
const bson = require("std/bson");
bson.parse("example");
```

## bson.stringify

`bson.stringify(value) -> data (opaque, do not read as text)`

```js
const bson = require("std/bson");
bson.stringify("example");
```
