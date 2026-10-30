import unittest

import carne
import carne/modules
import carne/std/uuid

registerStd("std/uuid", uuid.install)

test "uuid4 destructures and yields a v4 rfc4122 string":
  check runCode(
    "const {uuid4} = require('std/uuid'); uuid4().length") == "36"
  check runCode(
    "const {uuid4} = require('std/uuid'); " &
    "require('std/uuid').version(uuid4())") == "4"
  check runCode(
    "const {uuid4} = require('std/uuid'); " &
    "require('std/uuid').variant(uuid4())") == "rfc4122"

test "v4 method yields a v4 rfc4122 string":
  check runCode(
    "const uuid = require('std/uuid'); uuid.v4().length") == "36"
  check runCode(
    "const uuid = require('std/uuid'); uuid.version(uuid.v4())") == "4"

test "v1 v2 v6 v7 carry their version":
  check runCode("require('std/uuid').version(require('std/uuid').v1())") == "1"
  check runCode("require('std/uuid').version(require('std/uuid').v1())") == "1"
  check runCode(
    "require('std/uuid').version(require('std/uuid').uuid2(1, 501))") == "2"
  check runCode("require('std/uuid').version(require('std/uuid').v6())") == "6"
  check runCode("require('std/uuid').version(require('std/uuid').v7())") == "7"
  check runCode(
    "require('std/uuid').variant(require('std/uuid').v7())") == "rfc4122"

test "v3 and v5 match the RFC 4122 appendix B vectors":
  check runCode(
    "require('std/uuid').v3(require('std/uuid').NAMESPACE_DNS, " &
    "'www.widgets.com')") == "3d813cbb-47fb-32ba-91df-831e1593ac29"
  check runCode(
    "require('std/uuid').v5(require('std/uuid').NAMESPACE_DNS, " &
    "'www.widgets.com')") == "21f7f8de-8051-5b89-8680-0195ef798b6a"
  check runCode(
    "const u = require('std/uuid'); " &
    "u.uuid5(u.NAMESPACE_URL, 'https://x.io') === " &
    "u.v5(u.NAMESPACE_URL, 'https://x.io')") == "true"

test "v8 takes 32 hex chars and stamps version 8":
  check runCode(
    "require('std/uuid').version(require('std/uuid').v8(" &
    "'0123456789abcdef0123456789abcdef'))") == "8"
  check runCode(
    "require('std/uuid').v8('0123456789abcdef0123456789abcdef')") ==
    "01234567-89ab-8def-8123-456789abcdef"

test "parse normalizes case and dashes, throws when invalid":
  check runCode(
    "require('std/uuid').parse('F47AC10B58CC4372A5670E02B2C3D479')") ==
    "f47ac10b-58cc-4372-a567-0e02b2c3d479"
  expect CarneError:
    discard runCode("require('std/uuid').parse('nope')")

test "isValid answers without throwing":
  check runCode(
    "require('std/uuid').isValid('f47ac10b-58cc-4372-a567-0e02b2c3d479')") ==
    "true"
  check runCode("require('std/uuid').isValid('nope')") == "false"

test "nil constant and isNil":
  check runCode("require('std/uuid').NIL") ==
    "00000000-0000-0000-0000-000000000000"
  check runCode(
    "require('std/uuid').isNil(require('std/uuid').NIL)") == "true"
  check runCode(
    "require('std/uuid').isNil(require('std/uuid').v4())") == "false"

test "namespace constants hold the RFC values":
  check runCode("require('std/uuid').NAMESPACE_DNS") ==
    "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
  check runCode("require('std/uuid').NAMESPACE_URL") ==
    "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
  check runCode("require('std/uuid').NAMESPACE_OID") ==
    "6ba7b812-9dad-11d1-80b4-00c04fd430c8"
  check runCode("require('std/uuid').NAMESPACE_X500") ==
    "6ba7b814-9dad-11d1-80b4-00c04fd430c8"

test "version and variant throw when invalid":
  expect CarneError:
    discard runCode("require('std/uuid').version('nope')")
  expect CarneError:
    discard runCode("require('std/uuid').variant('nope')")

test "uuid rejects bad arity, types and ranges":
  expect CarneError:
    discard runCode("require('std/uuid').uuid4(42)")
  expect CarneError:
    discard runCode("require('std/uuid').parse(42)")
  expect CarneError:
    discard runCode("require('std/uuid').uuid2(999, 1)")
  expect CarneError:
    discard runCode("require('std/uuid').v3('nope', 'x')")
  expect CarneError:
    discard runCode("require('std/uuid').v8('short')")
