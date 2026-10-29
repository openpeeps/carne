import std/os
import unittest

import carne
import carne/pkg/loader
import carne/pkg/pkgman

proc freshHome(): string =
  result = getTempDir() / "carne_pkgreq_test"
  if dirExists(result):
    removeDir(result)
  createDir(result)

proc gitCommit(dir, msg: string) =
  discard execShellCmd("git -C " & quoteShell(dir) & " add -A")
  discard execShellCmd("git -C " & quoteShell(dir) &
    " -c user.email=t@t -c user.name=t commit -qm " & quoteShell(msg))

proc gitInit(dir: string) =
  discard execShellCmd("git -C " & quoteShell(dir) & " init -q")

proc gitTag(dir, tag: string) =
  discard execShellCmd("git -C " & quoteShell(dir) & " tag " & tag)

proc setupFixtures(home: string): DatpkgrConfig =
  result = newCarnePkgConfig(rootPath = home)
  # greet: two tagged versions, main + relative require chain.
  let greet = home / "repo-greet"
  createDir(greet / "src")
  writeFile(greet / "package.json",
    """{"name": "greet", "version": "0.1.0", "main": "src/index.js"}""")
  writeFile(greet / "src" / "index.js",
    "const u = require(\"./util\");\n" &
    "module.exports = { who: () => \"greet-0.1.0+\" + u.suffix() };\n")
  writeFile(greet / "src" / "util.js",
    "module.exports = { suffix: () => \"u1\" };\n")
  gitInit(greet)
  gitCommit(greet, "v1")
  gitTag(greet, "0.1.0")
  writeFile(greet / "src" / "index.js",
    "const u = require(\"./util\");\n" &
    "module.exports = { who: () => \"greet-0.2.0+\" + u.suffix() };\n")
  writeFile(greet / "src" / "util.js",
    "module.exports = { suffix: () => \"u2\" };\n")
  gitCommit(greet, "v2")
  gitTag(greet, "0.2.0")
  check result.pkgInstall("greet", url = greet)
  check result.pkgInstall("greet", url = greet & "#0.1.0")
  # expkg: exports map only (+ subpath file, no main).
  let expkg = home / "repo-expkg"
  createDir(expkg / "src")
  writeFile(expkg / "package.json", """{"name": "expkg", "version": "1.0.0",
    "exports": {".": "./src/entry.js"}}""")
  writeFile(expkg / "src" / "entry.js",
    "module.exports = { tag: () => \"entry\" };\n")
  writeFile(expkg / "extra.js",
    "module.exports = { tag: () => \"extra\" };\n")
  gitInit(expkg)
  gitCommit(expkg, "init")
  check result.pkgInstall("expkg", url = expkg)
  # both: main and exports (exports wins, Node parity).
  let both = home / "repo-both"
  createDir(both)
  writeFile(both / "package.json", """{"name": "both", "version": "1.0.0",
    "main": "main.js", "exports": {".": "./exp.js"}}""")
  writeFile(both / "main.js", "module.exports = { tag: () => \"main\" };\n")
  writeFile(both / "exp.js", "module.exports = { tag: () => \"exp\" };\n")
  gitInit(both)
  gitCommit(both, "init")
  check result.pkgInstall("both", url = both)
  # noentry: manifest only, nothing loadable.
  let noentry = home / "repo-noentry"
  createDir(noentry)
  writeFile(noentry / "package.json",
    """{"name": "noentry", "version": "1.0.0"}""")
  gitInit(noentry)
  gitCommit(noentry, "init")
  check result.pkgInstall("noentry", url = noentry)
  # esmpkg: ESM syntax, out of scope with a clear error.
  let esmpkg = home / "repo-esm"
  createDir(esmpkg)
  writeFile(esmpkg / "package.json",
    """{"name": "esmpkg", "version": "1.0.0", "main": "index.js"}""")
  writeFile(esmpkg / "index.js", "export const x = 1;\n")
  gitInit(esmpkg)
  gitCommit(esmpkg, "init")
  check result.pkgInstall("esmpkg", url = esmpkg)
  initPkgLoader(result)

test "require pkg main with relative chain":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  check runCode("require('pkg/greet').who()") == "greet-0.2.0+u2"

test "require pkg caches instances":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  check runCode("require('pkg/greet') === require('pkg/greet')") == "true"

test "require pkg pins @version":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  check runCode("require('pkg/greet@0.1.0').who()") == "greet-0.1.0+u1"

test "require pkg honors exports map and subpaths":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  check runCode("require('pkg/expkg').tag()") == "entry"
  check runCode("require('pkg/expkg/extra').tag()") == "extra"

test "exports wins over main":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  check runCode("require('pkg/both').tag()") == "exp"

test "require unknown package throws":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  expect CarneError:
    discard runCode("require('pkg/nope')")

test "require package without entry throws":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  expect CarneError:
    discard runCode("require('pkg/noentry')")

test "require ESM package throws":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  expect CarneError:
    discard runCode("require('pkg/esmpkg')")

test "relative require outside a package throws":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  expect CarneError:
    discard runCode("require('./x')")

test "runFile supports sibling relative requires":
  let home = freshHome()
  defer: removeDir(home)
  discard setupFixtures(home)
  let dir = home / "scripts"
  createDir(dir)
  writeFile(dir / "lib.js", "module.exports = { name: \"lib\" };\n")
  writeFile(dir / "main.js", "require(\"./lib\").name + \"!\";\n")
  check runFile(dir / "main.js") == "lib!"
