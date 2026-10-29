import unittest

import carne
import carne/modules
import carne/std/path

registerStd("std/path", path.install)

test "path parse local file":
  check runCode(
    "JSON.stringify(require('std/path').parse('/a/b/c.txt'))") ==
    """{"kind":"local","absolute":true,"segments":["a","b","c.txt"],""" &
    """"ext":"txt"}"""

test "path parse url with auth, port, query and fragment":
  check runCode(
    "JSON.stringify(require('std/path').parse(" &
    "'https://user@host:8080/p?q=1#frag'))") ==
    """{"kind":"web","scheme":"https","user":"user","host":"host",""" &
    """"port":8080,"path":"/p","segments":["p"],""" &
    """"query":[{"key":"q","value":"1"}],"fragment":"frag"}"""

test "path parse relative has no ext key":
  check runCode(
    "JSON.stringify(require('std/path').parse('a/b'))") ==
    """{"kind":"local","absolute":false,"segments":["a","b"]}"""
