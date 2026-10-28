import std/[options, os]
import unittest

import carne/pkg/pkgman

proc freshHome(): string =
  result = getTempDir() / "carne_pkgman_test"
  if dirExists(result):
    removeDir(result)
  createDir(result)

test "config roots at override and registers source":
  let home = freshHome()
  defer: removeDir(home)
  let cfg = newCarnePkgConfig(rootPath = home)
  check cfg.defaultSourceName == "carne"
  check cfg.defaultRegistryUrl == pkgRegistryUrl
  var found = false
  for src in cfg.loadSources():
    if src.name == "carne" and src.url == pkgRegistryUrl:
      found = true
  check found

test "pkg list on empty home does not raise":
  let home = freshHome()
  defer: removeDir(home)
  let cfg = newCarnePkgConfig(rootPath = home)
  cfg.pkgList()

test "develop + resolve roundtrip":
  let home = freshHome()
  defer: removeDir(home)
  let cfg = newCarnePkgConfig(rootPath = home)
  let pkgDir = home / "fixture-greet"
  createDir(pkgDir / "src")
  writeFile(pkgDir / "package.json", """{
    "name": "greet", "version": "0.1.0", "main": "src/greet.js"
  }""")
  writeFile(pkgDir / "src" / "greet.js", "console.log('hi');\n")
  check cfg.pkgDevelop(pkgDir)
  let resolved = cfg.resolvePkgImport("pkg/greet")
  check resolved.isSome
  check resolved.get == pkgDir / "src" / "greet.js"

test "resolve rejects unknown and escapes":
  let home = freshHome()
  defer: removeDir(home)
  let cfg = newCarnePkgConfig(rootPath = home)
  check cfg.resolvePkgImport("pkg/nonexistent").isNone
  check cfg.resolvePkgImport("std/env").isNone
  check cfg.resolvePkgImport("pkg/../escape").isNone
  check cfg.resolvePkgImport("pkg/").isNone

test "entry point fallbacks":
  let home = freshHome()
  defer: removeDir(home)
  let cfg = newCarnePkgConfig(rootPath = home)
  let noMain = home / "fixture-nomain"
  createDir(noMain)
  writeFile(noMain / "package.json",
    """{"name": "nomain", "version": "1.0.0"}""")
  writeFile(noMain / "index.js", "var a = 1;\n")
  check cfg.packageEntryPoint(noMain, "nomain") == noMain / "index.js"
  let empty = home / "fixture-empty"
  createDir(empty)
  check cfg.packageEntryPoint(empty, "empty") == ""
