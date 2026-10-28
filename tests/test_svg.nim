import unittest

import carne

test "svg parse element tree":
  check runCode(
    "JSON.stringify(require('std/svg').parse(" &
    "'<svg viewBox=\"0 0 10 10\"><circle cx=\"5\" cy=\"5\" r=\"4\"/></svg>'))") ==
    """{"kind":"element","tag":"svg","attrs":{"viewBox":"0 0 10 10"},""" &
    """"children":[{"kind":"element","tag":"circle",""" &
    """"attrs":{"cx":"5","cy":"5","r":"4"},"children":[]}]}"""

test "svg parse text leaves":
  check runCode(
    "JSON.stringify(require('std/svg').parse('<svg>hi</svg>')" &
    ".children[0])") ==
    """{"kind":"text","text":"hi"}"""

test "svg parse error throws":
  expect CarneError:
    discard runCode("require('std/svg').parse('<svg><unclosed>')")
