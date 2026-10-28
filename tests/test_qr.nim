import unittest

import carne

test "qr encode size and svg":
  check runCode(
    "require('std/qr').encode('hello').size") == "21"
  check runCode(
    "require('std/qr').encode('hello').svg.slice(0, 5)") == "<svg "
  check runCode(
    "require('std/qr').encode('hello', {ecLevel: 'H'}).size") == "21"
  check runCode(
    "require('std/qr').encode('hello').terminal.length > 0") == "true"

test "qr encode rejects bad ecLevel":
  expect CarneError:
    discard runCode("require('std/qr').encode('hi', {ecLevel: 'Z'})")
  expect CarneError:
    discard runCode("require('std/qr').encode('hi', 42)")

test "qr encode rejects overflow":
  expect CarneError:
    discard runCode("require('std/qr').encode('x'.repeat(5000))")
