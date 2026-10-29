import unittest

import carne
import carne/modules
import carne/std/plist

registerStd("std/plist", plist.install)

test "plist parse xml dict":
  let res = runCode(
    "JSON.stringify(require('std/plist').parse(" &
    "'<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>" &
    "<key>k</key><string>v</string><key>n</key><integer>3</integer>" &
    "</dict></plist>'))")
  check res == """{"k":"v","n":3}"""

test "plist stringify roundtrip":
  check runCode(
    "JSON.stringify(require('std/plist').parse(" &
    "require('std/plist').stringify({a: 'x', b: false})))") ==
    """{"a":"x","b":false}"""

test "plist parse error throws":
  expect CarneError:
    discard runCode("require('std/plist').parse('not a plist')")
