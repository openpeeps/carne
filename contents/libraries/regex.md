---
title: Regex
description: "Server-side regular expressions."
keywords: ['carne', 'javascript', 'std', 'regex']
---

# Regex

Server-side regular expressions. Same engine/semantics as Nim code using openparser. `exec` returns
`null` on no match.

```js
const regex = require("std/regex");
console.log(regex.test("\\d+", "abc123")); // true (search semantics)
console.log(regex.exec("(\\w+)@(\\w+)", "mail ada@x.io").match); // "ada@x"
console.log(regex.matchAll("a+", "aa b aaa").length); // 2
```


## regex.test

`regex.test(pattern, text) -> bool (search semantics)`

```js
const regex = require("std/regex");
regex.test("example", "example");
```

## regex.exec

`regex.exec(pattern, text) -> {match, index, groups} | null`

```js
const regex = require("std/regex");
regex.exec("example", "example");
```

## regex.matchAll

`regex.matchAll(pattern, text) -> [{match, index, groups}]`

```js
const regex = require("std/regex");
regex.matchAll("example", "example");
```
