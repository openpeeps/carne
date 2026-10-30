---
title: TOML
description: "TOML parsing and serialization."
keywords: ['carne', 'javascript', 'std', 'toml']
---

# TOML

TOML parsing and serialization. TOML datetimes surface as strings (the literal as written).

```js
const toml = require("std/toml");
const cfg = toml.parse('[server]\nhost = "localhost"\nport = 3000\n');
console.log(cfg.server.port); // 3000
console.log(toml.stringify(cfg));
```


## toml.parse

`toml.parse(text) -> object (document root must be a table)`

```js
const toml = require("std/toml");
toml.parse("example");
```

## toml.stringify

`toml.stringify(obj) -> string`

```js
const toml = require("std/toml");
toml.stringify("example");
```
