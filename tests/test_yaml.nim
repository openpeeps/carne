import std/json
import unittest

import carne
import carne/modules
import carne/std/yaml

registerStd("std/yaml", yaml.install)

test "yaml parse mapping":
  let res = runCode(
    "JSON.stringify(require('std/yaml').parse('name: ada\\nn: 3\\nflag: true'))")
  check res == """{"name":"ada","n":3,"flag":true}"""

test "yaml parse sequence and scalars":
  check runCode(
    "JSON.stringify(require('std/yaml').parse('- 1\\n- two\\n- false'))") ==
    """[1,"two",false]"""
  check runCode(
    "JSON.stringify(require('std/yaml').parse('just a string'))") ==
    "\"just a string\""

test "yaml stringify roundtrip":
  check runCode(
    "require('std/yaml').stringify(require('std/yaml').parse(" &
    "require('std/yaml').stringify({a: 1, b: [true, null]})))") ==
    runCode("require('std/yaml').stringify({a: 1, b: [true, null]})")

test "yaml parse error throws":
  expect CarneError:
    discard runCode("require('std/yaml').parse('{unclosed: [1,')")

test "yaml stringify rejects circular":
  expect CarneError:
    discard runCode(
      "const o = {}; o.self = o; require('std/yaml').stringify(o)")
