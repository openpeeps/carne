import unittest

import carne
import carne/modules
import carne/std/diff

registerStd("std/diff", diff.install)

test "diff identical inputs":
  check runCode(
    "JSON.stringify(require('std/diff').diff('same', 'same'))") ==
    """{"identical":true,"binary":false,"truncated":false,""" &
    """"stats":{"added":0,"removed":0,"changed":0,"hunks":0,""" &
    """"bytesAdded":0,"bytesRemoved":0},"hunks":[]}"""
  check runCode(
    "require('std/diff').unified('same', 'same')") == ""

test "diff changed lines":
  check runCode(
    "JSON.stringify(require('std/diff').diff('a\\nb\\nc\\n', 'a\\nx\\nc\\n')" &
    ".hunks[0].lines.map(l => l.kind + ':' + l.text))") ==
    """["equal:a","delete:b","insert:x","equal:c"]"""
  check runCode(
    "JSON.stringify(require('std/diff').diff('a\\nb\\n', 'a\\nc\\n')" &
    ".stats)") ==
    """{"added":1,"removed":1,"changed":1,"hunks":1,""" &
    """"bytesAdded":1,"bytesRemoved":1}"""

test "diff unified text":
  check runCode(
    "require('std/diff').unified('a\\nb\\n', 'a\\nc\\n')") ==
    "diff --git /dev/null /dev/null\n--- /dev/null\n+++ /dev/null\n" &
    "@@ -1,2 +1,2 @@\n a\n-b\n+c\n"

test "diff context option":
  check runCode(
    "require('std/diff').diff('1\\n2\\n3\\n4\\n5\\n6\\n', " &
    "'1\\n2\\nX\\n4\\n5\\n6\\n', {context: 1}).hunks[0].lines.length") == "4"
  check runCode(
    "require('std/diff').diff('1\\n2\\n3\\n4\\n5\\n6\\n', " &
    "'1\\n2\\nX\\n4\\n5\\n6\\n').hunks[0].lines.length") == "7"
  expect CarneError:
    discard runCode("require('std/diff').diff('a', 'b', {context: -2})")
