import unittest

import carne

test "toml parse document":
  let res = runCode(
    "JSON.stringify(require('std/toml').parse(" &
    "'title = \"hi\"\\ncount = 3\\npi = 3.5\\nok = true\\n[db]\\nport = 5432'))")
  check res == """{"title":"hi","count":3,"pi":3.5,"ok":true,"db":{"port":5432}}"""

test "toml datetime becomes string":
  check runCode(
    "require('std/toml').parse('d = 1979-05-27T07:32:00Z').d") ==
    "1979-05-27T07:32:00Z"

test "toml stringify roundtrip":
  check runCode(
    "JSON.stringify(require('std/toml').parse(" &
    "require('std/toml').stringify({a: 1, nested: {b: 'x'}})))") ==
    """{"a":1,"nested":{"b":"x"}}"""

test "toml parse error throws":
  expect CarneError:
    discard runCode("require('std/toml').parse('a = ')")

test "toml stringify rejects non-object root":
  expect CarneError:
    discard runCode("require('std/toml').stringify([1, 2])")

test "toml stringify rejects null":
  expect CarneError:
    discard runCode("require('std/toml').stringify({a: null})")
