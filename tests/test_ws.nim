import unittest

import carne
import carne/modules
import carne/std/ws

registerStd("std/ws", ws.install)

test "async echo roundtrip":
  check runCode(
    "const ws = require('std/ws'); " &
    "const log = []; " &
    "const srv = ws.serve(18201, {onMessage: (c, m) => " &
    "{ log.push('srv:' + m.data); c.send('echo:' + m.data); }}); " &
    "new Promise((resolve, reject) => { " &
    "const c = ws.connect('ws://127.0.0.1:18201/chat', { " &
    "onOpen: () => c.send('hello'), " &
    "onMessage: (m) => { log.push('cli:' + m.data + ':' + m.isBinary); " &
    "c.close(); ws.close(srv.port); resolve(log.join(',')); }, " &
    "onError: (e) => reject(new Error('conn:' + e.message))}); });") ==
    "srv:hello,cli:echo:hello:false"

test "connectSync echo roundtrip":
  check runCode(
    "const ws = require('std/ws'); " &
    "const srv = ws.serve(18202, {onMessage: (c, m) => " &
    "c.send('hi ' + m.data)}); " &
    "let done; " &
    "const p = new Promise((r) => { done = r; }); " &
    "const c = ws.connectSync('ws://127.0.0.1:18202/', " &
    "{onMessage: (m) => { c.close(); ws.close(srv.port); done(m.data); }}); " &
    "c.send('ada'); " &
    "p") == "hi ada"

test "serve returns port and host, close returns true":
  check runCode(
    "const ws = require('std/ws'); " &
    "const s = ws.serve(18203, '127.0.0.1', {}); " &
    "s.port + ':' + s.host + ':' + ws.close(s.port)") ==
    "18203:127.0.0.1:true"

test "server observes open and remote close with code":
  check runCode(
    "const ws = require('std/ws'); " &
    "const log = []; " &
    "const srv = ws.serve(18204, { " &
    "onOpen: (c) => log.push('open'), " &
    "onMessage: (c, m) => { log.push('msg:' + m.data); c.send('back'); }, " &
    "onClose: (c, e) => { log.push('closed:' + e.code + ':' + e.reason); " &
    "ws.close(srv.port); finish(log.join(',')); }}); " &
    "let finish; " &
    "const p = new Promise((r) => { finish = r; }); " &
    "const c = ws.connect('ws://127.0.0.1:18204/', { " &
    "onOpen: () => c.send('x'), " &
    "onMessage: (m) => { log.push('got:' + m.data); c.close(1000, 'bye'); }}); " &
    "p") == "open,msg:x,got:back,closed:1000:bye"

test "send on closed connection throws":
  expect CarneError:
    discard runCode(
      "const ws = require('std/ws'); " &
      "const srv = ws.serve(18205, {}); " &
      "const c = ws.connectSync('ws://127.0.0.1:18205/'); " &
      "c.close(); " &
      "c.send('x');")

test "connectSync to refused port throws":
  expect CarneError:
    discard runCode(
      "require('std/ws').connectSync('ws://127.0.0.1:18997/');")

test "async connect error surfaces via onError":
  check runCode(
    "const ws = require('std/ws'); " &
    "new Promise((resolve) => { " &
    "ws.connect('ws://127.0.0.1:18996/', " &
    "{onError: (e) => resolve(e.message.length > 0)}); });") == "true"

test "wss URLs are rejected":
  expect CarneError:
    discard runCode("require('std/ws').connect('wss://example.com/chat');")
  expect CarneError:
    discard runCode(
      "require('std/ws').connectSync('wss://example.com/chat');")

test "serve validates port and handlers":
  expect CarneError:
    discard runCode("require('std/ws').serve(99999, {});")
  expect CarneError:
    discard runCode("require('std/ws').serve(18206, 42);")
  expect CarneError:
    discard runCode(
      "require('std/ws').serve(18206, {onMessage: 42});")
  expect CarneError:
    discard runCode("require('std/ws').serve(18206);")

test "connect validates url and arity":
  expect CarneError:
    discard runCode("require('std/ws').connect();")
  expect CarneError:
    discard runCode("require('std/ws').connect(42);")
  expect CarneError:
    discard runCode("require('std/ws').connect('http://x/');")
  expect CarneError:
    discard runCode(
      "require('std/ws').connect('ws://127.0.0.1:18207/', 42);")

test "connectSync validates timeoutMs":
  expect CarneError:
    discard runCode(
      "require('std/ws').connectSync('ws://127.0.0.1:18208/', " &
      "{timeoutMs: 'soon'});")
  expect CarneError:
    discard runCode(
      "require('std/ws').connectSync('ws://127.0.0.1:18208/', " &
      "{timeoutMs: -5});")

test "close unknown port throws":
  expect CarneError:
    discard runCode("require('std/ws').close(18995)")

test "conn close validates code":
  expect CarneError:
    discard runCode(
      "const ws = require('std/ws'); " &
      "const srv = ws.serve(18209, {}); " &
      "const c = ws.connectSync('ws://127.0.0.1:18209/'); " &
      "c.close(42);")
