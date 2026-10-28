import unittest

import carne

test "xml parse element shape":
  let res = runCode(
    "JSON.stringify(require('std/xml').parse(" &
    "'<root a=\"1\"><child>hi</child><empty/></root>'))")
  check res == """{"tag":"root","attrs":{"a":"1"},"children":[{"tag":"child","attrs":{},"children":["hi"]},{"tag":"empty","attrs":{},"children":[]}]}"""

test "xml stringify roundtrip":
  check runCode(
    "require('std/xml').stringify(require('std/xml').parse(" &
    "'<root a=\"1\"><child>hi</child></root>'))") ==
    """<root a="1"><child>hi</child></root>"""

test "xml parse error throws":
  expect CarneError:
    discard runCode("require('std/xml').parse('<unclosed>')")

test "xml stringify validates shapes":
  expect CarneError:
    discard runCode("require('std/xml').stringify({tag: 42})")
  expect CarneError:
    discard runCode("require('std/xml').stringify('just a string')")
