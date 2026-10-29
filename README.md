<p align="center">
  <img src="https://github.com/openpeeps/carne/blob/main/.github/carne_logo.png" alt="Carne Logo" width="140px" height="140px"><br>
  Carne /kär-nē/ &bullet; a JavaScript runtime 👑 Written in Nim language
</p>

<p align="center">
  <code>nimble install carne</code> / <code>clue install carne --build</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/carne">API reference</a><br>
  <img src="https://github.com/openpeeps/carne/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/carne/workflows/docs/badge.svg" alt="Github Actions">
</p>

> [!NOTE]
> Carne is still experimental: it runs on macOS and Linux
> (Linux needs `libjavascriptcoregtk-4.1-dev` installed), the `std/*` API
> may change between 0.x releases, and a few modules are parse-only
> in v1 (see the Standard Library notes below). Scripts needing
> top-level `await` must wrap in an async IIFE for now. Not recommended
> for production yet, but the full test suite passes on both platforms
> and every example below is covered by it.

## About
A JavaScript runtime based on JavaScriptCore and Nim! No drama, no overhype. With a rich
standard library, so you don't need npm anymore! Still, it ships with an efficient package manager that
abolishes `node_modules` and keeps dependencies in one shared global store instead.

Carne is not a drop-in replacement for Node.js, Bun or Deno, instead it is a runtime with an opinion: most scripts
should not need a dependency at all. It trades the npm ocean for a standard library that covers
everyday work out of the box, starts in ~8 ms on the back of JavaScriptCore, and stays ~6k lines of Nim,
small enough to read in an afternoon. If you want the Node ecosystem, keep Node. If you want a
script that just runs, take Carne.

## 😍 Key Features
- JavaScript runtime powered by JavaScriptCore
- Powerful Standard Library fully written in Nim lang
- Cryptographic library via [pkg/nimcypher](https://github.com/nimbase/nimcypher)
- HTTP/1.1, H/2, UDP, TCP and WebSockets library via [pkg/powpow](https://github.com/openpeeps/powpow)
- Built-in formatters: `yaml`, `toml`, `csv`, `xml`, `markdown`, `vcard`, `feed`, `sql`, `colors`, `css`, `diff`, `qr`, `svg` via [pkg/openparser](https://github.com/openpeeps/openparser)
- JIT compiled Regex Engine
- i18n via GNU Gettext PO/MO
- CSS and JavaScript bundler via [pkg/squeezy](https://github.com/openpeeps/squeezy)
- Built-in package manager (`carne pkg`)
  - one shared global store in your home dir, no `node_modules`,
    no duplicated installs across projects
  - `install` (by name or `--url`), `remove`, `update`, `list`,
    `prune` orphans, `refresh` registry data
  - `develop <path>` for editable installs from a local directory
  - `package.json` manifests, npm-spec compliant; public registry
    coming (see Roadmap)
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

## Package manager
A DFS (depth-first search) package manager with one shared global store
(`~/.carne`, no `node_modules`), built on
[pkg/datpkgr](https://github.com/openpeeps/datpkgr), the same engine used
at [tim](https://github.com/openpeeps/tim),
[clue](https://github.com/openpeeps/clue),
[bowdy](https://github.com/openpeeps/bowdy). It installs from both git
and npm-style sources:

- `carne pkg install <git-url>` (or `--url=...` to pin a source URL):
  `https://` URLs, `git+`/`git://` transports, `git@` and `.git` URLs,
  plus forge aliases (`gh:user/repo`, long form `github:`; also `gl:`,
  `cb:`, `srht:`). A `#ref`
  suffix pins a branch or tag: `carne pkg install gh:user/repo#v1`.
  Works today.
- The cloned repo must contain a valid `package.json` at its root;
  anything else is rejected, not installed.
- `carne pkg install <name>[@range]`, `npm:name@range` aliases:
  resolved through the package registry.
- `carne pkg develop <path>`: editable installs from a local directory.
- `remove`, `update`, `list`, `prune`, `refresh` manage the store.

> [!NOTE]
> The public registry (`carne/pkgs`) is not set up yet, so installs by
> bare package name currently 404. Until it exists, install from git
> URLs or `develop` locally. See Roadmap.

### Package imports
Installed packages load through `require("pkg/<name>")` as CommonJS:
entry resolution reads the `exports` map root first, then `main`
(`index.js`, `src/index.js`, `<name>.js` fallbacks). A `@version`
suffix pins an installed version, `pkg/<name>/sub/path` reaches
inside, and `./...` requires work between package files (and from
`carne run` scripts, relative to the script).

```js
const demo = require("pkg/carne_demo_pkg");
console.log(demo.hello("ada")); // hi ada
```

A `@version` suffix pins an installed version
(`require("pkg/greet@0.1.0")`), and `pkg/<name>/sub/path` reaches
inside a package.

Only CommonJS v1: ESM (`import`/`export`) packages fail with a clear
error, as do packages with no loadable entry. Use an absolute path
with `carne pkg develop` (a relative path links the wrong directory).

## Standard Library

All modules load lazily via the global `require("std/<name>")`,
requiring one costs nothing until first use. Timers are globals
(No require needed), Node-style.

### `std/env`, process info and environment

```js
const env = require("std/env");
console.log(env.args());            // e.g. ["carne", "app.js", "--port", "3000"]
console.log(env.getenv("HOME"));    // string | undefined
console.log(env.cwd());             // current directory
env.exit(2);                        // terminate with exit code 2
```

### `std/fs`, synchronous file system access

```js
const fs = require("std/fs");
fs.writeFile("/tmp/hello.txt", "hi");
console.log(fs.readFile("/tmp/hello.txt")); // "hi" (throws on IOError)
console.log(fs.exists("/tmp/hello.txt"));   // true (files and dirs)
console.log(fs.readDir("/tmp"));             // ["hello.txt", ...]
fs.mkdir("/tmp/sub");                        // undefined
fs.remove("/tmp/hello.txt");                 // files only
```

### Timers, globals, no require

```js
setTimeout(() => console.log("later"), 100);          // -> numeric id
const id = setInterval(() => console.log("tick"), 1000);
clearInterval(id); // or clearTimeout(id)
```

Extra args are forwarded to the callback (`setTimeout((a) => console.log(a), 10, "x")`).
Timer throws are recorded as uncaught (exit 1 after drain) without killing
the remaining timers.

### `std/yaml`

YAML parsing and serialization. Single-document in v1: trailing documents after `---` are ignored.

```js
const yaml = require("std/yaml");
const doc = yaml.parse("name: ada\ntags:\n  - nim\n  - js\n");
console.log(doc.name);            // "ada"
console.log(yaml.stringify(doc)); // single YAML document
```

### `std/toml`

TOML parsing and serialization. TOML datetimes surface as strings (the literal as written).

```js
const toml = require("std/toml");
const cfg = toml.parse('[server]\nhost = "localhost"\nport = 3000\n');
console.log(cfg.server.port); // 3000
console.log(toml.stringify(cfg));
```

### `std/ical`

iCalendar parsing and serialization

```js
const ical = require("std/ical");
const cal = ical.parse("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTART:20260101T100000Z\r\nSUMMARY:Hi\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
console.log(cal.events.length);
console.log(ical.stringify(cal)); // a VCALENDAR document
```

Shape: `{events, todos, journals, timezones, others}`. Absent options
stay absent; dates serialize as `{value, tzid?}`, durations as `"P1DT2H"`
strings. Unknown properties ride along in `extraProps` and survive
the roundtrip.

### `std/dotenv`

`.env` file parsing

```js
const dotenv = require("std/dotenv");
console.log(dotenv.parse("PORT=3000\nHOST=localhost:$PORT\n"));
// {PORT: "3000", HOST: "localhost:3000"} (variable expansion applied)
dotenv.load();            // reads ./.env into process env (see std/env)
dotenv.load(".env", true); // ...overwriting existing vars
```

### `std/plist`, Apple property lists

```js
const plist = require("std/plist");
const v = plist.parse('<plist version="1.0"><dict><key>Name</key><string>Ada</string></dict></plist>');
console.log(v.Name);          // "Ada" (XML or binary plist in)
console.log(plist.stringify(v)); // XML plist out
```

### `std/bson`

BSON parsing and serialization. Raw BSON bytes travel with an opaque mapping (do not read the string
as text); `stringify` output always parses back.

```js
const bson = require("std/bson");
const blob = bson.stringify({name: "ada", n: 1});
console.log(JSON.stringify(bson.parse(blob))); // {"name":"ada","n":1}
```

### `std/csv`

CSV parsing. With `headers: true` the first row becomes keys and the result is an
array of objects.

```js
const csv = require("std/csv");
console.log(csv.parse("a,b\n1,2\n"));                  // [["a","b"],["1","2"]]
console.log(csv.parse("a,b\n1,2\n", {headers: true})); // [{a: "1", b: "2"}]
csv.parse("a;b\n1;2\n", {delimiter: ";"});              // custom delimiter/quote
```

### `std/xml`

XML parsing and serialization. Elements map to `{tag, attrs, children}`. Comments, prologs and doctypes
are dropped on parse.

```js
const xml = require("std/xml");
const node = xml.parse("<note><to>Ada</to></note>");
console.log(node.tag);                          // "note"
console.log(node.children[0].children[0]);      // "Ada" (text nodes are strings)
console.log(xml.stringify(node));
```

### `std/vcard`

vCard contact parsing. Parse-only in v1: there is no object-to-vCard builder yet.

```js
const vcard = require("std/vcard");
const contacts = vcard.parse("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n");
console.log(contacts.length); // 1 (one object per VCARD)
```

### `std/feed`

RSS and Atom feed parsing. Parse-only in v1

```js
const feed = require("std/feed");
const rss = feed.parseRss('<rss version="2.0"><channel><title>T</title><item><title>Hi</title></item></channel></rss>');
console.log(rss.items.length); // 1 (feed object with items[])
const atom = feed.parseAtom(text); // feed object with entries[]
```

### `std/sql`

SQL parsing and validation.

```js
const sql = require("std/sql");
const ast = sql.sqlite.parse("SELECT a FROM t"); // AST object ({kind, value?, quote?, children?})
console.log(sql.postgres.validate("SELECT $1"));      // {valid: true}
console.log(sql.mysql.validate("SELECT `a` FROM t")); // {valid: true}
```

One sub-namespace per dialect: `sqlite`, `postgres` (= `pgsql`), `mysql`.
Each has `parse(sql)` (throws a JS `Error` on syntax errors) and
`validate(sql)` (never throws, reports `{valid: false, error}` instead).

### `std/crypto`

hashing, AEAD sealing, signatures, passwords

```js
const crypto = require("std/crypto");
console.log(crypto.hash.sha256hex("abc")); // "ba7816bf8f01cfea..."

const stored = crypto.password.hash("s3cret");      // argon2id "salt:hash"
console.log(crypto.password.verify("s3cret", stored)); // true

const keys = crypto.sign.keypair(); // {publicKey, secretKey} hex (ed25519)
const sig = crypto.sign.sign(keys.secretKey, "msg");
console.log(crypto.sign.verify(keys.publicKey, "msg", sig)); // true

const keyHex = "00".repeat(32); // 32-byte key as hex
const env = crypto.aead.seal("secret", keyHex); // {nonce, mac, cipher} hex
console.log(crypto.aead.open(env, keyHex));     // "secret" (throws on MAC failure)
```

All binary values cross the boundary as lowercase hex strings. `open`
throws on MAC failure; `verify` returns `false` on mismatch instead.
X25519/RSA/ECDSA and AES modes are deferred.

### `std/path`

file-path and URL parsing. Parse-only in v1. Absent options stay absent.

```js
const path = require("std/path");
console.log(path.parse("/a/b/c.txt").ext); // "txt"
console.log(path.parse("/a/b/c.txt").segments); // ["a", "b", "c.txt"]
const web = path.parse("https://user@host:8080/p?q=1#frag");
console.log(web.host + web.path); // "host/p"
```

### `std/colors`

Color parsing, formatting and math

```js
const colors = require("std/colors");
console.log(colors.toHex(colors.parse("red"))); // "#ff0000"
console.log(colors.toRgb(colors.parse("red"))); // "rgb(255, 0, 0)"
console.log(colors.lighten(colors.parse("#333"), 20)); // {r, g, b, a}
console.log(colors.contrastRatio(colors.parse("black"), colors.parse("white"))); // 21
```

Colors cross the boundary as `{r, g, b, a}` objects. Accepts hex,
`rgb()`/`hsl()`/`hsv()`/`cmyk()` and named colors; also `darken`,
`saturate`, `spin`, `complement`, `greyscale`, `mix`, `triad`,
`isReadable`, `isLight`.

### `std/css`

CSS parsing and declaration validation

```js
const css = require("std/css");
console.log(css.parse("a { color: red; }").rules.length); // 1
console.log(css.validate("a { color: red; bogus: 1; }"));
// [{property: "bogus", valid: false, errors: [...]}] ([] when clean)
```

### `std/diff`

Unified diffs (Myers/patience/histogram)

```js
const diff = require("std/diff");
console.log(diff.diff("a\nb\n", "a\nc\n").identical); // false
console.log(diff.unified("a\nb\n", "a\nc\n", {context: 1}));
// "diff --git ...\n--- /dev/null\n+++ /dev/null\n@@ ...\n a\n-b\n+c\n"
```

`diff()` returns `{identical, stats, hunks}`; hunk lines are
`{kind: "equal"|"insert"|"delete", text, spans?}`. Both functions take
an optional `{context}` options object (default 3).

### `std/gettext`

`.po` parsing and translation. Untranslated ids fall back to the msgid. `.mo` is out of scope in v1.

```js
const gettext = require("std/gettext");
const po = 'msgid "hi"\nmsgstr "salut"\n';

console.log(gettext.translate(po, "hi")); // "salut"
console.log(gettext.ntranslate(po, "file", "files", 2));
console.log(gettext.parse(po).entries.length);
```

### `std/regex`

Server-side regular expressions. Same engine/semantics as Nim code using openparser. `exec` returns
`null` on no match.

```js
const regex = require("std/regex");
console.log(regex.test("\\d+", "abc123")); // true (search semantics)
console.log(regex.exec("(\\w+)@(\\w+)", "mail ada@x.io").match); // "ada@x"
console.log(regex.matchAll("a+", "aa b aaa").length); // 2
```

### `std/qr`

QR code generation (Model 2). Decoding is out of scope in v1.

```js
const qr = require("std/qr");
const code = qr.encode("hello"); // {size, svg, terminal}
console.log(code.size);          // 21
console.log(code.svg.slice(0, 5)); // "<svg "
qr.encode("hello", {ecLevel: "H"}); // higher error correction (L/M/Q/H)
```

### `std/svg`

SVG parsing. Elements map to `{tag, attrs, children}` (same shape as `std/xml`);
text, comments and CDATA become `{kind, text}` leaves. Serialization
is out of scope in v1, pair with `std/xml` when you need to write SVG.

```js
const svg = require("std/svg");
const node = svg.parse('<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>');
console.log(node.tag);              // "svg"
console.log(node.children.length);  // 1
```

### `std/http`

Async HTTP client + server, example:

```js
const http = require("std/http");

// Client (Promises; wrap in an async IIFE, no top-level await yet)
(async () => {
  const res = await http.get("https://example.com/");
  console.log(res.status, res.body.length); // 200 ...
  const posted = await http.post("https://example.com/api", "hi");
  const custom = await http.fetch("https://example.com/", {method: "PUT", body: "x"});
})();

// Server (stays alive until closed, like Node)
const srv = http.serve(3000, req => ({body: "hi " + req.path}));
http.close(srv.port);
```

`fetch(url[, {method, headers, body, timeoutMs}])` returns
`{status, statusText, headers, body}`. Handlers return a string, a
`{status?, headers?, body?}` object, or `undefined`; handler throws
become 500s. Client and server multiplex on one event loop with the
timers, truly async, no threads.

### `std/ws`

Async + sync WebSocket client and server, example:

```js
const ws = require("std/ws");

// Server (stays alive until closed, like Node)
const srv = ws.serve(8080, {
  onMessage: (conn, msg) => conn.send("hi " + msg.data)
});

// Async client (handshake on the loop; wrap in an async IIFE)
(async () => {
  const c = await ws.connect("ws://127.0.0.1:8080/chat", {
    onMessage: (msg) => {
      console.log(msg.data); // hi ada
      c.close();
      ws.close(srv.port);
    }
  });
  c.send("ada");
})();

// Sync client (blocks until open)
const c2 = ws.connectSync("ws://127.0.0.1:8080/chat");
c2.send("sync");
c2.close();
```

`connect(url[, handlers])` returns a Promise for the `{send, close}`
handle (`await ws.connect(...)` or `.then(...)`); `connectSync(url[,
{timeoutMs, ...handlers}])` pumps the same loop until open (default 10s).
Server callbacks get `(conn, payload)`, client callbacks just `(payload)`;
messages are `{data, isBinary}`, closes `{code, reason}`, errors
`{message}`. Handshake failures reject the promise (an `onError` handler
fires too when given). `ws://` only in v1, no TLS yet.

## Roadmap
- [x] JSC runtime: console/process/require/timers CLI
- [x] Package management (`carne pkg`, manifests)
- [x] Format std libs (yaml, toml, ical, dotenv, plist, bson, csv, xml, vcard, feed)
- [x] `std/sql`, `std/crypto`, `std/path`, `std/colors`
- [x] `std/css`, `std/diff`, `std/gettext`, `std/regex`, `std/qr`, `std/svg`
- [x] `std/http` (async client + server) + top-level promise unwrap in `runCode`
- [x] `std/ws` (async + sync client, server, no TLS)
- [x] Lazy startup (deferred event loop, per-run TLS, cached spec data)
- [x] Benchmark suite + results
- [ ] Top-level await in scripts (currently needs an async IIFE)
- [ ] `std/crypto`: X25519 exchange, RSA/ECDSA, AES-GCM
- [ ] `std/gettext`: `.mo` support; `std/qr`: decode; `std/svg`: stringify
- [ ] `exportClass` in the module DSL
- [ ] Public package registry (`carne/pkgs`)
- [x] Beyond macOS (Linux via JavaScriptCoreGTK 4.1)


## Benchmarks

Kinda useless JS bench suite (`bench/js`, via `hyperfine --warmup 2 --min-runs 3`,
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
