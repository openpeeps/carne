import unittest

import carne

const sampleCard =
  "\"BEGIN:VCARD\\r\\nVERSION:4.0\\r\\nFN:Ada Lovelace\\r\\n" &
  "N:Lovelace;Ada;;;\\r\\nEMAIL;TYPE=work:ada@example.com\\r\\n" &
  "TEL;TYPE=voice:+1000\\r\\nEND:VCARD\\r\\n\""

test "vcard parse contact":
  check runCode(
    "require('std/vcard').parse(" & sampleCard & ")[0].fn") ==
    "Ada Lovelace"
  check runCode(
    "require('std/vcard').parse(" & sampleCard & ")[0].n.family") ==
    "Lovelace"
  check runCode(
    "require('std/vcard').parse(" & sampleCard & ")[0].emails[0].value") ==
    "ada@example.com"
  check runCode(
    "JSON.stringify(require('std/vcard').parse(" & sampleCard &
    ")[0].tels[0].types)") == """["voice"]"""

test "vcard parse error throws":
  expect CarneError:
    discard runCode("require('std/vcard').parse('not a vcard')")
