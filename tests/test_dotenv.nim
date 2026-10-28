import std/os
import unittest

import carne

test "dotenv parse with expansion":
  let res = runCode(
    "JSON.stringify(require('std/dotenv').parse(" &
    "'A=1\\nB=\"x $A\"\\n# comment\\nexport C=plain'))")
  check res == """{"A":"1","B":"x 1","C":"plain"}"""

test "dotenv parse single quotes stay raw":
  check runCode(
    "require('std/dotenv').parse(\"A='no $expand'\").A") == "no $expand"

test "dotenv load writes process env":
  let p = getTempDir() / "carne_dotenv_test"
  defer: removeFile(p)
  writeFile(p, "CARNE_DOTENV_TESTKEY=ok456\n")
  discard runCode("require('std/dotenv').load('" & p & "')")
  check runCode("require('std/env').getenv('CARNE_DOTENV_TESTKEY')") ==
    "ok456"

test "dotenv load missing file is a no-op":
  discard runCode(
    "require('std/dotenv').load('/no/such/carne_dotenv_xyz')")

test "dotenv parse error shape":
  expect CarneError:
    discard runCode("require('std/dotenv').parse('x', 'y')")
