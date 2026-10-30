---
title: YAML
description: "YAML parsing and serialization."
keywords: ['carne', 'javascript', 'std', 'yaml']
---

# YAML

YAML parsing and serialization. Single-document in v1: trailing documents after `---` are ignored.

```js
const yaml = require("std/yaml");
const doc = yaml.parse("name: ada\ntags:\n  - nim\n  - js\n");
console.log(doc.name);            // "ada"
console.log(yaml.stringify(doc)); // single YAML document
```


## yaml.parse

`yaml.parse(text) -> value (objects, arrays, scalars)`

```js
const yaml = require("std/yaml");
yaml.parse("example");
```

## yaml.stringify

`yaml.stringify(value) -> string (single YAML document)`

```js
const yaml = require("std/yaml");
yaml.stringify("example");
```
