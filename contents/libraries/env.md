---
title: Env
description: "Process info and environment variables."
keywords: ['carne', 'javascript', 'std', 'env', 'process', 'environment']
---

# Env

```js
const env = require("std/env");
console.log(env.args());            // e.g. ["carne", "app.js", "--port", "3000"]
console.log(env.getenv("HOME"));    // string | undefined
console.log(env.cwd());             // current directory
env.exit(2);                        // terminate with exit code 2
```


## env.args

`env.args() -> process.argv as a fresh array`

```js
const env = require("std/env");
env.args();
```

## env.getenv

`env.getenv("HOME") -> string | undefined`

```js
const env = require("std/env");
env.getenv("key");
```

## env.cwd

`env.cwd() -> string`

```js
const env = require("std/env");
env.cwd();
```

## env.exit

`env.exit(2) -> terminates the run with exit code 2`

```js
const env = require("std/env");
env.exit(1000);
```
