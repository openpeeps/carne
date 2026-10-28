import unittest

import carne

const preamble = "(async () => { const http = require('std/http'); "

test "fetch roundtrip returns status and body":
  check runCode(preamble &
    "const srv = http.serve(18101, req => ({body: 'hi ' + req.path})); " &
    "const res = await http.fetch('http://127.0.0.1:18101/test'); " &
    "http.close(srv.port); " &
    "return res.status + ':' + res.body; })()") == "200:hi /test"

test "serve returns port and host, close returns true":
  check runCode(preamble &
    "const srv = http.serve(18102, '127.0.0.1', req => ({})); " &
    "const s = srv.port + ':' + srv.host; " &
    "const c = http.close(srv.port); " &
    "return s + ':' + c; })()") == "18102:127.0.0.1:true"

test "get and post with headers and body":
  check runCode(preamble &
    "const srv = http.serve(18103, req => ({status: 201, " &
    "headers: {'X-Echo': req.headers['x-test'] || 'none'}, " &
    "body: req.method + ':' + req.body})); " &
    "const res = await http.post('http://127.0.0.1:18103/e', 'ping', " &
    "{headers: {'X-Test': 'yes'}}); " &
    "const g = await http.get('http://127.0.0.1:18103/e'); " &
    "http.close(srv.port); " &
    "return res.status + ':' + res.headers['x-echo'] + ':' + res.body + " &
    "'|GET:' + g.body; })()") ==
    "201:yes:POST:ping|GET:GET:"

test "request path query url and status text":
  check runCode(preamble &
    "const srv = http.serve(18104, req => " &
    "({body: [req.path, req.query, req.url].join('|')})); " &
    "const res = await http.get('http://127.0.0.1:18104/a/b?x=1&y=2'); " &
    "http.close(srv.port); " &
    "return res.statusText + ':' + res.body; })()") ==
    "OK:/a/b|x=1&y=2|/a/b?x=1&y=2"

test "handler string return is text plain":
  check runCode(preamble &
    "const srv = http.serve(18105, req => 'plain'); " &
    "const res = await http.get('http://127.0.0.1:18105/'); " &
    "http.close(srv.port); " &
    "return res.status + ':' + res.headers['content-type'] + ':' + " &
    "res.body; })()") ==
    "200:text/plain; charset=utf-8:plain"

test "handler status codes pass through":
  check runCode(preamble &
    "const srv = http.serve(18106, req => " &
    "req.path === '/old' ? {status: 404, body: 'gone'} : {body: 'here'}); " &
    "const a = await http.get('http://127.0.0.1:18106/old'); " &
    "const b = await http.get('http://127.0.0.1:18106/new'); " &
    "http.close(srv.port); " &
    "return a.status + ':' + a.body + ' ' + b.status + ':' + b.body; " &
    "})()") == "404:gone 200:here"

test "concurrent fetches all resolve":
  check runCode(preamble &
    "const srv = http.serve(18107, req => ({body: 'r' + req.path})); " &
    "const rs = await Promise.all([" &
    "http.get('http://127.0.0.1:18107/1'), " &
    "http.fetch('http://127.0.0.1:18107/2', {method: 'GET'}), " &
    "http.post('http://127.0.0.1:18107/3', 'b')]); " &
    "http.close(srv.port); " &
    "return rs.map(r => r.body).join(','); })()") == "r/1,r/2,r/3"

test "connection refused rejects":
  expect CarneError:
    discard runCode(preamble &
      "await http.get('http://127.0.0.1:18999/nope'); })()")

test "handler throw answers 500 and raises uncaught":
  expect CarneError:
    discard runCode(preamble &
      "const srv = http.serve(18108, req => { throw new Error('kaput'); }); " &
      "const res = await http.get('http://127.0.0.1:18108/'); " &
      "http.close(srv.port); })()")
  check runCode(preamble &
    "const srv = http.serve(18109, req => ({status: 500, body: 'oops'})); " &
    "const res = await http.get('http://127.0.0.1:18109/'); " &
    "http.close(srv.port); " &
    "return res.status + ':' + res.body; })()") == "500:oops"

test "fetch unknown method throws":
  expect CarneError:
    discard runCode(preamble &
      "await http.fetch('http://127.0.0.1:18109/', " &
      "{method: 'BOGUS'}); })()")

test "serve validates port and handler":
  expect CarneError:
    discard runCode(preamble & "http.serve(99999, () => ({})); })()")
  expect CarneError:
    discard runCode(preamble & "http.serve(18110, 'nope'); })()")
  expect CarneError:
    discard runCode("require('std/http').serve(18111)")

test "close unknown port throws":
  expect CarneError:
    discard runCode("require('std/http').close(18998)")

test "fetch validates arity and options":
  expect CarneError:
    discard runCode("require('std/http').fetch()")
  expect CarneError:
    discard runCode(preamble &
      "await http.fetch('http://127.0.0.1:18112/', 42); })()")
  expect CarneError:
    discard runCode(preamble &
      "await http.get('http://127.0.0.1:18112/', " &
      "{method: 'POST'}); })()")
