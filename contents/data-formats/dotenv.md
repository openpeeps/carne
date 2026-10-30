---
title: Dotenv
description: ".env file parsing and loading."
keywords: ['carne', 'javascript', 'std', 'dotenv', 'env']
---

# Dotenv

`.env` file parsing

```js
const dotenv = require("std/dotenv");
console.log(dotenv.parse("PORT=3000\nHOST=localhost:$PORT\n"));
// {PORT: "3000", HOST: "localhost:3000"} (variable expansion applied)
dotenv.load();            // reads ./.env into process env (see std/env)
dotenv.load(".env", true); // ...overwriting existing vars
```


## dotenv.parse

`dotenv.parse(text) -> object (with variable expansion applied)`

```js
const dotenv = require("std/dotenv");
dotenv.parse("example");
```

## dotenv.load

`dotenv.load([path][, override]) -> undefined (writes into process env)`

```js
const dotenv = require("std/dotenv");
dotenv.load("/tmp/demo.txt", "example");
```
