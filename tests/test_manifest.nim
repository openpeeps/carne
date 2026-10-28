import std/[json, os, strutils, tables]
import unittest

import carne/pkg/pkgmanifest

const validFull = """{
  "name": "myutils",
  "version": "0.1.0",
  "description": "handy string helpers",
  "license": "MIT",
  "keywords": ["strings", "utils"],
  "homepage": "https://example.com/myutils",
  "main": "src/myutils.js",
  "scripts": {"test": "carne run test.js"},
  "engines": {"carne": ">=0.1.0"},
  "dependencies": {
    "otherlib": "^0.2.0",
    "exactlib": "1.2.3",
    "anylib": "*",
    "latestlib": "latest",
    "aliased": "npm:realname@^2.0.0",
    "gitlib": "git+https://example.com/gitlib.git",
    "ghlab": "github:user/repo"
  },
  "devDependencies": {"testlib": "~1.0.0"},
  "optionalDependencies": {"optlib": ">=2.0.0"},
  "peerDependencies": {"peerlib": "^3.0.0"}
}"""

test "full package.json parses":
  let m = parsePackageManifest(validFull, "package.json")
  check m.name == "myutils"
  check m.version == "0.1.0"
  check m.description == "handy string helpers"
  check m.license == "MIT"
  check m.dependencies.len == 7
  check m.devDependencies.len == 2
  check m.extra["main"].getStr() == "src/myutils.js"
  check m.extra["peerDependencies"]["peerlib"].getStr() == "^3.0.0"
  check m.extra["scripts"]["test"].getStr() == "carne run test.js"

test "dep specs map correctly":
  let m = parsePackageManifest(validFull, "package.json")
  var byName: Table[string, string] = initTable[string, string]()
  for d in m.dependencies:
    byName[d.name] = $d.constraint.kind
  check byName["otherlib"] == "vcCaret"
  check byName["exactlib"] == "vcExact"
  check byName["anylib"] == "vcAny"
  check byName["latestlib"] == "vcAny"
  check byName["realname"] == "vcCaret"
  for d in m.dependencies:
    if d.name == "realname":
      check d.url == ""
    if d.name == "gitlib":
      check d.url == "git+https://example.com/gitlib.git"
    if d.name == "ghlab":
      check d.url == "github:user/repo"

test "minimal manifest parses":
  let m = parsePackageManifest(
    """{"name": "tiny", "version": "1.0.0-beta.1"}""", "package.json")
  check m.name == "tiny"
  check m.version == "1.0.0-beta.1"
  check m.dependencies.len == 0

test "legacy license object coerces":
  let m = parsePackageManifest(
    """{"name": "a", "version": "1.0.0",
        "license": {"type": "ISC", "url": "https://example.com"}}""",
    "package.json")
  check m.license == "ISC"

test "missing name fails with path":
  try:
    discard parsePackageManifest("""{"version": "1.0.0"}""", "pkg/package.json")
    fail()
  except PackageManifestError as e:
    check "pkg/package.json" in e.msg
    check "name" in e.msg

test "bad names fail":
  for bad in ["MyLib", ".hidden", "_priv", "@scope/name", "has space",
      "has/slash", "bad~char", ""]:
    expect PackageManifestError:
      discard parsePackageManifest(
        "{\"name\": \"" & bad & "\", \"version\": \"1.0.0\"}", "package.json")

test "bad versions fail":
  for bad in ["", "^1.0.0", "latest", "1.0", "notaversion"]:
    expect PackageManifestError:
      discard parsePackageManifest(
        "{\"name\": \"a\", \"version\": \"" & bad & "\"}", "package.json")

test "missing version fails":
  expect PackageManifestError:
    discard parsePackageManifest("""{"name": "a"}""", "package.json")

test "non-object top level fails":
  expect PackageManifestError:
    discard parsePackageManifest("""[1, 2]""", "package.json")

test "malformed JSON fails with path":
  try:
    discard parsePackageManifest("""{"name": """, "pkg/package.json")
    fail()
  except PackageManifestError as e:
    check "pkg/package.json" in e.msg

test "unsupported dep specs fail":
  for spec in ["file:../local", "workspace:*",
      "https://example.com/a.tgz", "^1.0.0 || ^2.0.0", "1.2.3 - 2.0.0",
      "beta", "1.2.x"]:
    expect PackageManifestError:
      discard parsePackageManifest(
        "{\"name\": \"a\", \"version\": \"1.0.0\", \"dependencies\": {\"d\": \"" &
        spec & "\"}}", "package.json")

test "non-string dep spec fails":
  expect PackageManifestError:
    discard parsePackageManifest(
      """{"name": "a", "version": "1.0.0",
          "dependencies": {"d": 42}}""", "package.json")

test "bad license fails":
  expect PackageManifestError:
    discard parsePackageManifest(
      """{"name": "a", "version": "1.0.0", "license": 42}""", "package.json")
  expect PackageManifestError:
    discard parsePackageManifest(
      """{"name": "a", "version": "1.0.0",
          "license": {"url": "https://example.com"}}""", "package.json")

test "finder walks up":
  let base = getTempDir() / "carne_manifest_test"
  let sub = base / "a" / "b"
  createDir(sub)
  defer: removeDir(base)
  writeFile(base / "package.json", """{"name": "x", "version": "1.0.0"}""")
  check findPackageJson(sub) == base / "package.json"

test "finder returns empty when absent":
  let base = getTempDir() / "carne_manifest_empty"
  createDir(base)
  defer: removeDir(base)
  check findPackageJson(base) == ""

test "manifestMain reads main":
  let m = parsePackageManifest(validFull, "package.json")
  check m.manifestMain() == "src/myutils.js"
  let m2 = parsePackageManifest(
    """{"name": "a", "version": "1.0.0"}""", "package.json")
  check m2.manifestMain() == ""
