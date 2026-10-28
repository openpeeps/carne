import unittest

import carne

test "regex test searches like RegExp":
  check runCode("require('std/regex').test('\\\\d+', 'abc123')") == "true"
  check runCode("require('std/regex').test('^\\\\d+$', 'abc123')") == "false"
  check runCode("require('std/regex').test('^\\\\d+$', '123')") == "true"

test "regex exec returns match, index and groups":
  check runCode(
    "JSON.stringify(require('std/regex').exec('(\\\\w+)@(\\\\w+)', " &
    "'mail ada@x.io'))") ==
    """{"match":"ada@x","index":5,"groups":["ada","x"]}"""
  check runCode(
    "require('std/regex').exec('z+', 'abc')") == "null"

test "regex exec marks non-participating groups null":
  check runCode(
    "JSON.stringify(require('std/regex').exec('(a)|(b)', 'b').groups)") ==
    """[null,"b"]"""

test "regex matchAll collects every hit":
  check runCode(
    "JSON.stringify(require('std/regex').matchAll('a+', 'aa b aaa')" &
    ".map(m => m.match))") == """["aa","aaa"]"""
  check runCode(
    "JSON.stringify(require('std/regex').matchAll('z+', 'abc'))") == "[]"

test "regex bad pattern throws with usage":
  expect CarneError:
    discard runCode("require('std/regex').test('(unclosed', 'x')")
