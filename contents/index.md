---
title: Introduction
description: "Carne is a JavaScript runtime based on JavaScriptCore and Nim, with a rich standard library so you do not need npm."
keywords: ["carne", "javascript", "runtime", "nim", "javascriptcore", "standard library"]
---

# Carne

A JavaScript runtime based on JavaScriptCore and [Nim](https://nim-lang.org). No drama, no overhype. With a rich standard library, so you do not need npm anymore. It ships with an efficient package manager that abolishes `node_modules` and keeps dependencies in one shared global store instead.

This is not a drop-in replacement for Node.js, Bun or Deno. It is a runtime with an opinion: most scripts should not need a dependency at all. It trades the
npm ocean for a standard library that covers everyday work out of the box, starts
in ~8 ms on the back of JavaScriptCore, and stays ~6k lines of Nim, small enough
to read in an afternoon. If you want the Node ecosystem, keep Node. If you want a
script that just runs, take Carne.

## Key features

- JavaScript runtime powered by JavaScriptCore
- Powerful standard library fully written in Nim
- Cryptographic library via [pkg/nimcypher](https://github.com/nimbase/nimcypher)
- HTTP/1.1, HTTP/2, UDP, TCP and WebSockets via [pkg/powpow](https://github.com/openpeeps/powpow)
- Built-in formatters: `yaml`, `toml`, `csv`, `xml`, `markdown`, `vcard`, `feed`,
  `sql`, `colors`, `css`, `diff`, `qr`, `svg`
- i18n via GNU Gettext PO/MO
- CSS and JavaScript bundler via [pkg/squeezy](https://github.com/openpeeps/squeezy)
- Built-in package manager (`carne pkg`)
- Written in Nim, MIT License

## Quick start

```js
// hello.js
console.log("hello from carne");
```

```text
carne run hello.js
```

## Standard library

All modules load lazily via the global `require("std/<name>")`; requiring one
costs nothing until first use. Timers are globals (no require needed).

See the [Libraries](libraries) section for per-module documentation.

## Package manager

Carne ships a DFS package manager with one shared global store (`~/.carne`,
no `node_modules`). See the [Package manager](package-manager) page.

## Status

<div class="alert alert-info rounded-4" role="alert">
  <div class="alert-content">

    Carne is still experimental: it runs on macOS and Linux (Linux needs
`libjavascriptcoregtk-4.1-dev`), the `std/*` API may change between 0.x
releases, and a few modules are parse-only in v1. Scripts needing top-level
`await` must wrap in an async IIFE for now.

  </div>
</div>


## ❤ Contributions & Support

- Found a bug? [Create a new Issue](https://github.com/openpeeps/carne/issues)
- Wanna help? [Fork it!](https://github.com/openpeeps/carne/fork)

## License

MIT license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).
