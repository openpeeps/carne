<p align="center">
  <img src="https://github.com/openpeeps/carne/blob/main/.github/carne_logo.png" alt="CarneJS Logo" width="140px" height="140px"><br>
  Carne, a JavaScript runtime  👑 Written in Nim language
</p>

<p align="center">
  <code>nimble install carne</code> / <code>clue install carne --build</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/carne">API reference</a><br>
  <img src="https://github.com/openpeeps/carne/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/carne/workflows/docs/badge.svg" alt="Github Actions">
</p>

## 😍 Key Features
- JavaScript runtime powered by JavaScriptCore
- Powerful Standard Library
- Bun/Node-like CLI: `carne run script.js` (or bare `carne script.js`)
- `console.log`, `process.argv`, global `require("std/...")`
- Timers (`setTimeout`, `setInterval`, ...) on the powpow event loop
- Packages via `carne pkg` (npm-spec `package.json`, datpkgr backend)
- std libs: `env fs timers` + formats (`yaml toml ical dotenv plist bson csv xml vcard feed`)
- `sql` (sqlite/postgres/mysql AST + validate), `crypto` (hash/aead/sign/argon2id)
- `path colors css diff gettext regex qr svg`
- `http` (async fetch/get/post + serve on the shared powpow loop)
- `init`/`exportObject`/`registerFn` DSL for authoring std modules
- Written in Nim language
- Open Source | `MIT` License

### Usage

```
A JavaScript runtime in Nim
  (c) OpenPeeps | MIT License
  Build Version: 0.1.0

usage: carne <command> [args] [options]

Scripting
  run <script.js> [args]  run a .js file

Packages
  pkg install <spec>      install a package by name, git URL (--url=... pins a source URL)
  pkg remove <name> [ver] uninstall a package (one version, or all)
  pkg update [name]       update one package, or all when omitted
  pkg list                list installed packages
  pkg develop <path>      editable install from a local directory
  pkg prune               remove orphaned packages
  pkg refresh             re-download registry data

  -h, --help              show this help
  --version               show version
```

## Roadmap
- [x] JSC runtime: console/process/require/timers CLI
- [x] Package management (`carne pkg`, manifests)
- [x] Format std libs (yaml, toml, ical, dotenv, plist, bson, csv, xml, vcard, feed)
- [x] `std/sql`, `std/crypto`, `std/path`, `std/colors`
- [x] `std/css`, `std/diff`, `std/gettext`, `std/regex`, `std/qr`, `std/svg`
- [x] `std/http` (async client + server) + top-level promise unwrap in `runCode`
- [x] Benchmark suite + results
- [ ] Top-level await in scripts (currently needs an async IIFE)
- [ ] `std/crypto`: X25519 exchange, RSA/ECDSA, AES-GCM
- [ ] `std/gettext`: `.mo` support; `std/qr`: decode; `std/svg`: stringify
- [ ] `exportClass` in the module DSL
- [ ] Public package registry (`carne/pkgs`)
- [ ] Beyond macOS

## Examples
...

## Benchmarks

Shared JS bench suite (`bench/js`, via `hyperfine --warmup 2 --min-runs 3`,
macOS, `bench/run.sh` reproduces; node v22.22.1, bun 1.4.3):

| Benchmark | carne | node | bun |
|-----------|-------|------|-----|
| fib_recursive | 42.4 ms ± 0.5 ms | 85.1 ms ± 1.1 ms | 45.5 ms ± 1.0 ms |
| nested_loops | 9.3 ms ± 0.4 ms | 36.3 ms ± 0.7 ms | 11.9 ms ± 0.4 ms |
| prime_sieve | 9.2 ms ± 0.3 ms | 35.0 ms ± 0.5 ms | 11.7 ms ± 0.3 ms |
| string_concat | 9.4 ms ± 0.3 ms | 34.5 ms ± 0.5 ms | 11.7 ms ± 0.7 ms |
| tail_recursive | 9.7 ms ± 0.3 ms | CRASHED | 11.8 ms ± 0.3 ms |
| range_sum | 38.4 ms ± 0.4 ms | 43.8 ms ± 0.4 ms | 19.6 ms ± 0.3 ms |
| collatz | 51.1 ms ± 0.4 ms | 69.5 ms ± 0.7 ms | 53.4 ms ± 2.3 ms |
| array_sum | 14.6 ms ± 0.5 ms | 40.7 ms ± 0.9 ms | 16.8 ms ± 0.3 ms |
| bubble_sort | 11.8 ms ± 0.3 ms | 36.7 ms ± 0.4 ms | 14.5 ms ± 0.3 ms |
| object_access | 11.3 ms ± 0.3 ms | 36.9 ms ± 0.4 ms | 14.0 ms ± 0.3 ms |
| float_math | 12.9 ms ± 0.3 ms | 39.1 ms ± 1.0 ms | 16.5 ms ± 0.4 ms |
| call_overhead | 10.4 ms ± 0.2 ms | 35.5 ms ± 0.4 ms | 12.5 ms ± 0.3 ms |
| fizzbuzz_count | 43.8 ms ± 0.4 ms | 64.8 ms ± 0.6 ms | 38.3 ms ± 0.4 ms |

A cold `hello.js` run costs carne ~8.5 ms, so everything near that floor is
startup-dominated (JSC context + stdlib install), not compute. Node crashes
`tail_recursive` (no proper tail calls: stack overflow at 10k frames);
carne inherits JSC's tail-call support, like bun.

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/carne/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/carne/fork)

### 🎩 License
MIT license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
