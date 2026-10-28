import std/os
import unittest

import carne

proc tmpPath(name: string): string =
  getTempDir() / ("carne_test_" & name)

test "fs write/read roundtrip":
  let p = tmpPath("rw.txt")
  defer: removeFile(p)
  discard runCode("require('std/fs').writeFile('" & p & "', 'abc123')")
  check runCode("require('std/fs').readFile('" & p & "')") == "abc123"

test "fs read missing throws":
  expect CarneError:
    discard runCode("require('std/fs').readFile('/no/such/carne_file_xyz')")

test "fs exists files and dirs":
  let p = tmpPath("ex.txt")
  defer: removeFile(p)
  check runCode("require('std/fs').exists('" & p & "')") == "false"
  writeFile(p, "x")
  check runCode("require('std/fs').exists('" & p & "')") == "true"
  check runCode("require('std/fs').exists('" & getTempDir() & "')") == "true"

test "fs readDir lists names":
  let d = tmpPath("dir")
  createDir(d)
  defer: removeDir(d)
  writeFile(d / "a.txt", "a")
  writeFile(d / "b.txt", "b")
  let res = runCode("require('std/fs').readDir('" & d & "').sort().join(',')")
  check res == "a.txt,b.txt"

test "fs mkdir and remove":
  let d = tmpPath("mkdir")
  defer: removeDir(d)
  discard runCode("require('std/fs').mkdir('" & d & "')")
  check dirExists(d)
  let f = d / "gone.txt"
  writeFile(f, "x")
  discard runCode("require('std/fs').remove('" & f & "')")
  check not fileExists(f)
