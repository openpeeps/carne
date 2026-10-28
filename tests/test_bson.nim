import unittest

import carne

test "bson stringify/parse roundtrip":
  check runCode(
    "JSON.stringify(require('std/bson').parse(require('std/bson').stringify(" &
    "{hello: 'world', n: 42, t: true, z: null, a: [1, 'x'], o: {k: 'v'}})))") ==
    """{"hello":"world","n":42,"t":true,"z":null,"a":[1,"x"],"o":{"k":"v"}}"""

test "bson parse rejects text":
  expect CarneError:
    discard runCode("require('std/bson').parse('just text')")
