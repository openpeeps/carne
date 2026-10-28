<p align="center">
  <img src="https://github.com/openpeeps/PKG/blob/main/.github/logo.png" width="90px"><br>
  OpenPeeps repository template for developing libraries,<br>projects and other cool things. 👑 Written in Nim language
</p>

<p align="center">
  <code>nimble install {PKG}</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/{pkg}">API reference</a><br>
  <img src="https://github.com/openpeeps/pistachio/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/pistachio/workflows/docs/badge.svg" alt="Github Actions">
</p>

## 😍 Key Features
- Open Source | `MIT` License
- Written in Nim language
- macOS JavaScript runtime on the system JavaScriptCore
- Bun/Node-like CLI: `carne run script.js` (or bare `carne script.js`)
- `console.log`, `process.argv`, global `require("std/...")`
- Timers (`setTimeout`, `setInterval`, ...) on the powpow event loop
- Packages via `carne pkg` (npm-spec `package.json`, datpkgr backend)
- std libs: `env fs timers` + formats (`yaml toml ical dotenv plist bson csv xml vcard feed`)
- `sql` (sqlite/postgres/mysql AST + validate), `crypto` (hash/aead/sign/argon2id)
- `path colors css diff gettext regex qr svg`
- `init`/`exportObject`/`registerFn` DSL for authoring std modules

## Roadmap
- [x] JSC runtime: console/process/require/timers CLI
- [x] Package management (`carne pkg`, manifests)
- [x] Format std libs (yaml, toml, ical, dotenv, plist, bson, csv, xml, vcard, feed)
- [x] `std/sql`, `std/crypto`, `std/path`, `std/colors`
- [x] `std/css`, `std/diff`, `std/gettext`, `std/regex`, `std/qr`, `std/svg`
- [x] Benchmark suite + results
- [ ] `std/crypto`: X25519 exchange, RSA/ECDSA, AES-GCM
- [ ] `std/gettext`: `.mo` support; `std/qr`: decode; `std/svg`: stringify
- [ ] `exportClass` in the module DSL
- [ ] Public package registry (`carne/pkgs`)
- [ ] Beyond macOS

## Examples
...

## Benchmarks

Against dfkup's JS bench suite (`bench/js`, via `hyperfine --warmup 2 --min-runs 3`,
macOS, `bench/run.sh` reproduces):

| Benchmark | carne |
|-----------|-------|
| fib_recursive | 42.8 ms ± 1.8 ms |
| nested_loops | 9.5 ms ± 0.3 ms |
| prime_sieve | 9.2 ms ± 0.3 ms |
| string_concat | 9.4 ms ± 0.4 ms |
| tail_recursive | 9.7 ms ± 0.3 ms |
| range_sum | 38.9 ms ± 1.3 ms |
| collatz | 51.3 ms ± 0.4 ms |
| array_sum | 14.6 ms ± 0.4 ms |
| bubble_sort | 11.7 ms ± 0.4 ms |
| object_access | 11.5 ms ± 0.6 ms |
| float_math | 13.0 ms ± 0.3 ms |
| call_overhead | 10.4 ms ± 0.3 ms |
| fizzbuzz_count | 43.7 ms ± 0.4 ms |

A cold `hello.js` run costs ~8.5 ms, so everything in the 9–14 ms band is
startup-dominated (JSC context + stdlib install), not compute. Only fib,
range_sum, collatz, and fizzbuzz visibly exceed the floor.

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/pistachio/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/pistachio/fork)

### 🎩 License
MIT license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
