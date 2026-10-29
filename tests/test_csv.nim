import unittest

import carne
import carne/modules
import carne/std/csv

registerStd("std/csv", csv.install)

test "csv parse rows":
  check runCode(
    "JSON.stringify(require('std/csv').parse('a,b\\n1,2\\n\"x,y\",3\\n'))") ==
    """[["a","b"],["1","2"],["x,y","3"]]"""

test "csv parse with headers":
  check runCode(
    "JSON.stringify(require('std/csv').parse(" &
    "'name,age\\nada,36\\ngrace,85', {headers: true}))") ==
    """[{"name":"ada","age":"36"},{"name":"grace","age":"85"}]"""

test "csv parse custom delimiter":
  check runCode(
    "JSON.stringify(require('std/csv').parse('a;b\\n1;2', {delimiter: ';'}))") ==
    """[["a","b"],["1","2"]]"""

test "csv parse empty gives empty array":
  check runCode(
    "JSON.stringify(require('std/csv').parse(''))") == "[]"

test "csv ragged headers fill blanks":
  check runCode(
    "JSON.stringify(require('std/csv').parse('a,b\\n1', {headers: true}))") ==
    """[{"a":"1","b":""}]"""
