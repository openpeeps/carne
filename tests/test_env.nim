import std/os
import unittest

import carne
import carne/modules
import carne/std/env

registerStd("std/env", env.install)

test "env.args mirrors argv":
  check runCode("require('std/env').args().join(',')",
    argv = @["carne", "a.js", "x"]) == "carne,a.js,x"

test "env.getenv returns values":
  putEnv("CARNE_TEST_VAR", "hello123")
  check runCode("require('std/env').getenv('CARNE_TEST_VAR')") == "hello123"

test "env.getenv missing is undefined":
  delEnv("CARNE_TEST_MISSING")
  check runCode("require('std/env').getenv('CARNE_TEST_MISSING')") == ""

test "env.cwd matches process":
  check runCode("require('std/env').cwd()") == getCurrentDir()

test "env.exit sets exit code":
  let res = runCodeEx("require('std/env').exit(3)")
  check res.code == 3
  check res.output == ""
