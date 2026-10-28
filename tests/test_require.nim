import std/strutils
import unittest

import carne

test "require unknown module raises":
  expect CarneError:
    discard runCode("require('std/nope')")

test "require unknown module message":
  try:
    discard runCode("require('std/nope')")
    fail()
  except CarneError as e:
    check "unknown module" in e.msg

test "require caches instances":
  check runCode("require('std/env') === require('std/env')") == "true"

test "require needs exactly one arg":
  expect CarneError:
    discard runCode("require()")
