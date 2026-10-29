import std/os
import unittest

import carne
import carne/modules
import carne/std/fs

registerStd("std/fs", fs.install)

proc tmpPath(name: string): string =
  getTempDir() / ("carne_test_" & name)

test "setTimeout fires and drains":
  let p = tmpPath("t1.txt")
  defer: removeFile(p)
  discard runCode("const fs = require('std/fs'); " &
    "setTimeout(() => fs.writeFile('" & p & "', 'fired'), 10)")
  check readFile(p) == "fired"

test "timer order follows delay":
  let p = tmpPath("t2.txt")
  defer: removeFile(p)
  discard runCode("const fs = require('std/fs'); " &
    "setTimeout(() => fs.writeFile('" & p & "', require('std/fs').readFile('" &
    p & "') + 'slow;'), 30); " &
    "setTimeout(() => fs.writeFile('" & p & "', 'fast;'), 5)")
  check readFile(p) == "fast;slow;"

test "setInterval with clearInterval":
  let p = tmpPath("t3.txt")
  defer: removeFile(p)
  discard runCode("const fs = require('std/fs'); let n = 0; " &
    "const id = setInterval(() => { n++; " &
    "if (n == 3) { clearInterval(id); fs.writeFile('" & p & "', String(n)); } }, 10)")
  check readFile(p) == "3"

test "clearTimeout prevents fire":
  let p = tmpPath("t4.txt")
  let done = tmpPath("t4done.txt")
  defer: removeFile(p)
  defer: removeFile(done)
  discard runCode("const fs = require('std/fs'); " &
    "const id = setTimeout(() => fs.writeFile('" & p & "', 'x'), 50); " &
    "clearTimeout(id); " &
    "setTimeout(() => fs.writeFile('" & done & "', 'done'), 10)")
  check readFile(done) == "done"
  check not fileExists(p)

test "timer rest args passthrough":
  let p = tmpPath("t5.txt")
  defer: removeFile(p)
  discard runCode("const fs = require('std/fs'); " &
    "setTimeout((a, b) => fs.writeFile('" & p & "', a + b), 10, 'x', 'y')")
  check readFile(p) == "xy"

test "uncaught timer error raises after drain":
  expect CarneError:
    discard runCode("setTimeout(() => { throw new Error('late boom'); }, 10)")

test "setTimeout validates args":
  expect CarneError:
    discard runCode("setTimeout('nope', 10)")
  expect CarneError:
    discard runCode("setTimeout()")

test "run without timers returns immediately":
  check runCode("40 + 2") == "42"
