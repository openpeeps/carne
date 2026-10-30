---
title: Package manager
description: "The Carne DFS package manager with one shared global store."
keywords: ["carne", "package manager", "pkg", "packages", "npm"]
---

# Package manager

A DFS (depth-first search) package manager with one shared global store
(`~/.carne`, no `node_modules`), built on
[pkg/datpkgr](https://github.com/openpeeps/datpkgr). It installs from both git
and npm-style sources.

## Commands

```text
carne pkg install <spec>
carne pkg remove <name> [ver]
carne pkg update [name]
carne pkg list
carne pkg develop <path>
carne pkg prune
carne pkg refresh
carne pkg publish [opts]
```

## Installing from git

```text
carne pkg install <git-url>
carne pkg install gh:user/repo#v1
```

Supported sources include `https://` URLs, `git+`/`git://` transports, `git@`
and `.git` URLs, plus forge aliases (`gh:`, `github:`, `gl:`, `cb:`,
`srht:`). A `#ref` suffix pins a branch or tag.

The cloned repo must contain a valid `package.json` at its root.

## Installing from the registry

```text
carne pkg install <name>[@range]
carne pkg install npm:name@range
```

Resolved through the public registry at
[openpeeps/carnepkgs](https://github.com/openpeeps/carnepkgs) (source `carne`,
cached at `~/.carne/registries/carne.json`; `carne pkg refresh` re-downloads it).

## Package imports

Installed packages load through `require("pkg/<name>")` as CommonJS:

```js
const demo = require("pkg/carne_demo_pkg");
console.log(demo.hello("ada")); // hi ada
```

A `@version` suffix pins an installed version
(`require("pkg/greet@0.1.0")`), and `pkg/<name>/sub/path` reaches inside a
package. `./...` requires work between package files.

Only CommonJS v1 is supported: ESM (`import`/`export`) packages fail with a
clear error, as do packages with no loadable entry.
