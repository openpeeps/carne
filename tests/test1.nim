import unittest

import carne

test "eval arithmetic returns completion value":
  check runCode("1 + 2") == "3"

test "JSON.stringify roundtrip":
  check runCode("JSON.stringify({a: [1, 2]})") == "{\"a\":[1,2]}"

test "process.argv is installed":
  check runCode("process.argv.join(',')",
    argv = @["carne", "a.js", "x"]) == "carne,a.js,x"

test "js exceptions raise CarneError":
  expect CarneError:
    discard runCode("throw new Error('boom')")

test "syntax errors raise CarneError":
  expect CarneError:
    discard runCode("function ({")

test "undefined result returns empty string":
  check runCode("var a = 1;") == ""
