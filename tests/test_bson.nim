import unittest

import carne

test "bson stringify/parse roundtrip":
  check runCode(
    "JSON.stringify(require('std/bson').parse(require('std/bson').stringify(" &
    "{hello: 'world', n: 42, t: true, z: null, a: [1, 'x'], o: {k: 'v'}})))") ==
    """{"hello":"world","n":42,"t":true,"z":null,"a":[1,"x"],"o":{"k":"v"}}"""

test "bson roundtrip with floats and unicode":
  check runCode(
    "JSON.stringify(require('std/bson').parse(require('std/bson').stringify(" &
    "{price: 9.99, neg: -0.5, s: 'héllo wörld ✓', big: 123456789})))") ==
    """{"price":9.99,"neg":-0.5,"s":"héllo wörld ✓","big":123456789}"""

test "bson parse rejects text":
  expect CarneError:
    discard runCode("require('std/bson').parse('just text')")
