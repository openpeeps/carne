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

test "object completion does not crash thenable check":
  check runCode("JSON.stringify(({a: 1}))") ==
    """{"a":1}"""
  check runCode("JSON.stringify([1, 2])") == "[1,2]"
  check runCode("typeof ({})") == "object"

test "non-callable then is not unwrapped":
  check runCode("JSON.stringify(({then: 42}))") == """{"then":42}"""

test "top-level promise completion unwraps":
  check runCode("Promise.resolve(5)") == "5"
  check runCode("(async () => 7)()") == "7"
  expect CarneError:
    discard runCode("Promise.reject(new Error('nope'))")
