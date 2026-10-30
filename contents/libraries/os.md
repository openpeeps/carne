---
title: OS
description: "Synchronous OS utilities: files, directories, processes."
keywords: ['carne', 'javascript', 'std', 'os', 'filesystem', 'process']
---

# OS

File and dir access plus process helpers. Everything throws a JS
Error on failure; `sleep` and `exec` block the loop.

```js
const os = require("std/os");
os.writeFile("/tmp/hello.txt", "hi");
os.appendFile("/tmp/hello.txt", "!");
console.log(os.readFile("/tmp/hello.txt")); // "hi!" (throws on IOError)
console.log(os.exists("/tmp/hello.txt"));   // true (files and dirs)
console.log(os.isFile("/tmp/hello.txt"));   // true
console.log(os.readDir("/tmp"));             // [{name: "hello.txt", kind: "file"}, ...]
console.log(os.stat("/tmp/hello.txt").size); // 3
os.mkdir("/tmp/a/b", true);                  // recursive parents
os.copy("/tmp/hello.txt", "/tmp/hi.txt");
os.move("/tmp/hi.txt", "/tmp/ho.txt");
os.remove("/tmp/ho.txt");                    // files only
os.removeDir("/tmp/a", true);                // recursive tree delete
console.log(os.tmpdir(), os.homedir());      // dirs (plus configDir/cacheDir)
console.log(os.pid());                       // process id
os.sleep(10);                                // ms, blocks
console.log(os.exec("echo hi").output.trim()); // {code: 0, output: "hi\n"}
```


## os.readFile

`os.readFile(path) -> string (throws on IOError)`

```js
const os = require("std/os");
os.readFile("/tmp/demo.txt");
```

## os.writeFile

`os.writeFile(path, data) -> undefined`

```js
const os = require("std/os");
os.writeFile("/tmp/demo.txt", "example");
```

## os.appendFile

`os.appendFile(path, data) -> undefined`

```js
const os = require("std/os");
os.appendFile("/tmp/demo.txt", "example");
```

## os.exists

`os.exists(path) -> bool (files and dirs)`

```js
const os = require("std/os");
os.exists("/tmp/demo.txt");
```

## os.isFile

`os.isFile(path) -> bool`

```js
const os = require("std/os");
os.isFile("/tmp/demo.txt");
```

## os.isDir

`os.isDir(path) -> bool`

```js
const os = require("std/os");
os.isDir("/tmp/demo.txt");
```

## os.readDir

`os.readDir(path) -> [{name, kind}]`

```js
const os = require("std/os");
os.readDir("/tmp/demo.txt");
```

## os.mkdir

`os.mkdir(path[, recursive]) -> undefined`

```js
const os = require("std/os");
os.mkdir("/tmp/demo.txt", "example");
```

## os.remove

`os.remove(path) -> undefined (files only)`

```js
const os = require("std/os");
os.remove("/tmp/demo.txt");
```

## os.removeDir

`os.removeDir(path[, recursive]) -> undefined`

```js
const os = require("std/os");
os.removeDir("/tmp/demo.txt", "example");
```

## os.copy

`os.copy(src, dst) -> undefined (files)`

```js
const os = require("std/os");
os.copy("/tmp/demo.txt", "/tmp/demo.txt");
```

## os.move

`os.move(src, dst) -> undefined (files and dirs)`

```js
const os = require("std/os");
os.move("/tmp/demo.txt", "/tmp/demo.txt");
```

## os.stat

`os.stat(path) -> {size, kind, mtimeMs, atimeMs}`

```js
const os = require("std/os");
os.stat("/tmp/demo.txt");
```

## os.tmpdir

`os.tmpdir() -> temp directory path`

```js
const os = require("std/os");
os.tmpdir();
```

## os.homedir

`os.homedir() -> home directory path`

```js
const os = require("std/os");
os.homedir();
```

## os.configDir

`os.configDir() -> config directory path`

```js
const os = require("std/os");
os.configDir();
```

## os.cacheDir

`os.cacheDir() -> cache directory path`

```js
const os = require("std/os");
os.cacheDir();
```

## os.pid

`os.pid() -> current process id`

```js
const os = require("std/os");
os.pid();
```

## os.sleep

`os.sleep(ms) -> undefined (blocks the loop)`

```js
const os = require("std/os");
os.sleep(10);
```

## os.exec

`os.exec(cmd) -> {code, output} (blocks the loop)`

```js
const os = require("std/os");
os.exec("echo hi");
```
