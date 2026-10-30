import unittest

import carne
import carne/modules
import carne/std/ws

registerStd("std/ws", ws.install)

test "await connect echo roundtrip":
  check runCode(
    "const ws = require('std/ws'); " &
    "const log = []; " &
    "const srv = ws.serve(18201, {onMessage: (c, m) => " &
    "{ log.push('srv:' + m.data); c.send('echo:' + m.data); }}); " &
    "let done; " &
    "const gate = new Promise((r) => { done = r; }); " &
    "(async () => { " &
    "const c = await ws.connect('ws://127.0.0.1:18201/chat', { " &
    "onOpen: () => log.push('open'), " &
    "onMessage: (m) => { log.push('cli:' + m.data + ':' + m.isBinary); " &
    "c.close(); ws.close(srv.port); done(log.join(',')); }, " &
    "onError: (e) => { throw new Error('conn:' + e.message); }}); " &
    "c.send('hello'); })(); " &
    "gate") ==
    "open,srv:hello,cli:echo:hello:false"

test "connect then style resolves to the handle":
  check runCode(
    "const ws = require('std/ws'); " &
    "const srv = ws.serve(18210, {onMessage: (c, m) => " &
    "c.send('back:' + m.data)}); " &
    "new Promise((resolve, reject) => { " &
    "let cc; " &
    "ws.connect('ws://127.0.0.1:18210/', { " &
    "onMessage: (m) => { cc.close(); ws.close(srv.port); " &
    "resolve(m.data + ':' + (typeof cc.send)); }, " &
    "onError: (e) => reject(new Error(e.message))}) " &
    ".then((c) => { cc = c; c.send('hi'); }); });") ==
    "back:hi:function"

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
    "(async () => { " &
    "const c = await ws.connect('ws://127.0.0.1:18204/', " &
    "{onMessage: (m) => { log.push('got:' + m.data); " &
    "c.close(1000, 'bye'); }}); " &
    "c.send('x'); })(); " &
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

test "connect promise rejects on refused port":
  check runCode(
    "const ws = require('std/ws'); " &
    "(async () => { " &
    "try { await ws.connect('ws://127.0.0.1:18996/'); return 'resolved?!'; } " &
    "catch (e) { return 'rejected:' + (e.message.length > 0); } })();") ==
    "rejected:true"

test "wss handshake failure rejects instead of throwing at parse":
  check runCode(
    "const ws = require('std/ws'); " &
    "(async () => { " &
    "try { await ws.connect('wss://127.0.0.1:18996/'); " &
    "return 'resolved?!'; } " &
    "catch (e) { return 'rejected:' + (e.message.length > 0); } })();") ==
    "rejected:true"
  expect CarneError:
    discard runCode(
      "require('std/ws').connectSync('wss://127.0.0.1:18997/', " &
      "{timeoutMs: 2000});")

test "binary send roundtrip keeps flags":
  check runCode(
    "const ws = require('std/ws'); " &
    "const srv = ws.serve(18211, {onMessage: (c, m) => " &
    "c.send('bin:' + m.data + ':' + m.isBinary)}); " &
    "let done; " &
    "const p = new Promise((r) => { done = r; }); " &
    "const c = ws.connectSync('ws://127.0.0.1:18211/', " &
    "{onMessage: (m) => { c.close(); ws.close(srv.port); " &
    "done(m.data + ':' + m.isBinary); }}); " &
    "c.send('hi', {binary: true}); " &
    "p") == "bin:hi:true:false"

test "ping and protocol on an open conn":
  check runCode(
    "const ws = require('std/ws'); " &
    "const srv = ws.serve(18212, {onMessage: (c, m) => " &
    "c.send('echo:' + m.data)}); " &
    "let done; " &
    "const p = new Promise((r) => { done = r; }); " &
    "let info = ''; " &
    "const c = ws.connectSync('ws://127.0.0.1:18212/', " &
    "{onMessage: (m) => { c.close(); ws.close(srv.port); " &
    "done(info + '|' + m.data); }}); " &
    "info = typeof c.ping + ':' + typeof c.protocol + ':' + " &
    "c.protocol() + ':' + c.ping('x') + ':' + c.ping(); " &
    "c.send('still-open'); " &
    "p") == "function:function::true:true|echo:still-open"

test "connect forwards handshake opts":
  check runCode(
    "const ws = require('std/ws'); " &
    "const srv = ws.serve(18213, {onMessage: (c, m) => " &
    "c.send('hi ' + m.data)}); " &
    "let done; " &
    "const p = new Promise((r) => { done = r; }); " &
    "(async () => { " &
    "const c = await ws.connect('ws://127.0.0.1:18213/', { " &
    "headers: {'X-Test': 'yes'}, protocols: ['chat'], timeoutMs: 5000, " &
    "pingIntervalMs: 0, idleTimeoutMs: 0, maxFrameSize: 1048576, " &
    "onMessage: (m) => { const pr = c.protocol(); c.close(); " &
    "ws.close(srv.port); done(pr + ':' + m.data); }}); " &
    "c.send('ada'); })(); " &
    "p") == ":hi ada"

test "connect and send validate the new opts":
  expect CarneError:
    discard runCode(
      "require('std/ws').connectSync('ws://127.0.0.1:18214/', " &
      "{protocols: 'chat'});")
  expect CarneError:
    discard runCode(
      "require('std/ws').connectSync('ws://127.0.0.1:18214/', " &
      "{headers: 42});")
  expect CarneError:
    discard runCode(
      "require('std/ws').connectSync('ws://127.0.0.1:18214/', " &
      "{maxFrameSize: -1});")
  expect CarneError:
    discard runCode(
      "const ws = require('std/ws'); " &
      "const srv = ws.serve(18214, {}); " &
      "const c = ws.connectSync('ws://127.0.0.1:18214/'); " &
      "c.send('x', {binary: 42});")

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
    discard runCode(
      "(async () => { await require('std/ws').connect('http://x/'); })();")
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
