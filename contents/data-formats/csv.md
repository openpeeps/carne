---
title: CSV
description: "CSV parsing."
keywords: ['carne', 'javascript', 'std', 'csv']
---

# CSV

CSV parsing. With `headers: true` the first row becomes keys and the result is an
array of objects.

```js
const csv = require("std/csv");
console.log(csv.parse("a,b\n1,2\n"));                  // [["a","b"],["1","2"]]
console.log(csv.parse("a,b\n1,2\n", {headers: true})); // [{a: "1", b: "2"}]
csv.parse("a;b\n1;2\n", {delimiter: ";"});              // custom delimiter/quote
```


## csv.parse

`csv.parse(text[, {headers, delimiter, quote}]) -> array`

```js
const csv = require("std/csv");
csv.parse("example", {});
```
