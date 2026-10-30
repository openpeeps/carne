---
title: CSS
description: "CSS parsing and declaration validation."
keywords: ['carne', 'javascript', 'std', 'css']
---

# CSS

CSS parsing and declaration validation

```js
const css = require("std/css");
console.log(css.parse("a { color: red; }").rules.length); // 1
console.log(css.validate("a { color: red; bogus: 1; }"));
// [{property: "bogus", valid: false, errors: [...]}] ([] when clean)
```


## css.parse

`css.parse(text) -> {rules: [...]}`

```js
const css = require("std/css");
css.parse("example");
```

## css.validate

`css.validate(text) -> problems per declaration ([] when clean)`

```js
const css = require("std/css");
css.validate("example");
```
