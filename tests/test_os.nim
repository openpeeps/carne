from std/os import `/`, createDir, dirExists, fileExists, getTempDir,
  pcDir, removeDir, removeFile, walkDir
import unittest

import carne
import carne/modules
from carne/std/os import install
## Both std/os (above) and carne/std/os bind the name `os`: never
## qualify with bare `os` in this file, use `install` unqualified.

registerStd("std/os", install)

proc tmpPath(name: string): string =
  getTempDir() / ("carne_test_" & name)

proc rmTree(d: string) =
  for k, p in walkDir(d):
    if k == pcDir:
      rmTree(p)
    else:
      removeFile(p)
  removeDir(d)

test "os write/read roundtrip":
  let p = tmpPath("rw.txt")
  defer: removeFile(p)
  discard runCode("require('std/os').writeFile('" & p & "', 'abc123')")
  check runCode("require('std/os').readFile('" & p & "')") == "abc123"

test "os appendFile appends":
  let p = tmpPath("append.txt")
  defer: removeFile(p)
  discard runCode("require('std/os').writeFile('" & p & "', 'ab')")
  discard runCode("require('std/os').appendFile('" & p & "', 'cd')")
  check runCode("require('std/os').readFile('" & p & "')") == "abcd"

test "os read missing throws":
  expect CarneError:
    discard runCode("require('std/os').readFile('/no/such/carne_file_xyz')")

test "os exists, isFile and isDir":
  let p = tmpPath("ex.txt")
  defer: removeFile(p)
  check runCode("require('std/os').exists('" & p & "')") == "false"
  check runCode("require('std/os').isFile('" & p & "')") == "false"
  writeFile(p, "x")
  check runCode("require('std/os').exists('" & p & "')") == "true"
  check runCode("require('std/os').isFile('" & p & "')") == "true"
  check runCode("require('std/os').isDir('" & p & "')") == "false"
  check runCode("require('std/os').exists('" & getTempDir() & "')") == "true"
  check runCode("require('std/os').isDir('" & getTempDir() & "')") == "true"
  check runCode("require('std/os').isFile('" & getTempDir() & "')") == "false"

test "os readDir lists name and kind objects":
  let d = tmpPath("dir")
  createDir(d)
  defer: removeDir(d)
  writeFile(d / "a.txt", "a")
  createDir(d / "sub")
  defer: removeDir(d / "sub")
  check runCode(
    "JSON.stringify(require('std/os').readDir('" & d & "')" &
    ".sort((x, y) => x.name < y.name ? -1 : 1))") ==
    """[{"name":"a.txt","kind":"file"},{"name":"sub","kind":"dir"}]"""

test "os readDir missing throws":
  expect CarneError:
    discard runCode("require('std/os').readDir('/no/such/carne_dir_xyz')")

test "os mkdir and remove":
  let d = tmpPath("mkdir")
  defer: removeDir(d)
  discard runCode("require('std/os').mkdir('" & d & "')")
  check dirExists(d)
  let f = d / "gone.txt"
  writeFile(f, "x")
  discard runCode("require('std/os').remove('" & f & "')")
  check not fileExists(f)

test "os mkdir recursive creates parents":
  let d = tmpPath("deep") / "a" / "b"
  defer: rmTree(tmpPath("deep"))
  discard runCode("require('std/os').mkdir('" & d & "', true)")
  check dirExists(d)

test "os removeDir recursive deletes trees":
  let d = tmpPath("tree")
  createDir(d)
  writeFile(d / "f.txt", "x")
  createDir(d / "sub")
  writeFile(d / "sub" / "g.txt", "y")
  discard runCode("require('std/os').removeDir('" & d & "', true)")
  check not dirExists(d)

test "os copy and move roundtrip":
  let src = tmpPath("cp_src.txt")
  let dst = tmpPath("cp_dst.txt")
  let moved = tmpPath("cp_moved.txt")
  defer: removeFile(dst)
  defer: removeFile(moved)
  writeFile(src, "payload")
  defer: removeFile(src)
  discard runCode(
    "require('std/os').copy('" & src & "', '" & dst & "')")
  check readFile(dst) == "payload"
  discard runCode(
    "require('std/os').move('" & dst & "', '" & moved & "')")
  check readFile(moved) == "payload"
  check not fileExists(dst)

test "os stat reports size, kind and times":
  let p = tmpPath("stat.txt")
  defer: removeFile(p)
  writeFile(p, "12345")
  check runCode(
    "require('std/os').stat('" & p & "').size") == "5"
  check runCode(
    "require('std/os').stat('" & p & "').kind") == "file"
  check runCode(
    "require('std/os').stat('" & getTempDir() & "').kind") == "dir"
  check runCode(
    "const s = require('std/os').stat('" & p & "'); " &
    "s.mtimeMs > 0 && s.atimeMs > 0") == "true"

test "os stat missing throws":
  expect CarneError:
    discard runCode("require('std/os').stat('/no/such/carne_file_xyz')")

test "os dir helpers return non-empty paths":
  check runCode("require('std/os').tmpdir().length > 0") == "true"
  check runCode("require('std/os').homedir().length > 0") == "true"
  check runCode("require('std/os').configDir().length > 0") == "true"
  check runCode("require('std/os').cacheDir().length > 0") == "true"

test "os pid is positive":
  check runCode("require('std/os').pid() > 0") == "true"

test "os sleep waits and rejects negatives":
  check runCode("typeof require('std/os').sleep(5)") == "undefined"
  expect CarneError:
    discard runCode("require('std/os').sleep(-1)")

test "os exec captures code and output":
  check runCode(
    "JSON.stringify(require('std/os').exec('echo hi').output.trim())") ==
    "\"hi\""
  check runCode("require('std/os').exec('echo hi').code") == "0"
  check runCode("require('std/os').exec('exit 3').code") == "3"

test "os rejects bad arity and types":
  expect CarneError:
    discard runCode("require('std/os').readFile()")
  expect CarneError:
    discard runCode("require('std/os').readFile(42)")
  expect CarneError:
    discard runCode("require('std/os').writeFile('x')")
