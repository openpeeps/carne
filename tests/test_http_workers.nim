import unittest

import carne
import carne/modules
import carne/std/http
import carne/std/os
import carne/std/ws

registerStd("std/http", http.install)
registerStd("std/os", os.install)
registerStd("std/ws", ws.install)

# Workers re-run the whole script, so driver code (fetch/close,
# assertions scaffolding) is gated on process.isWorker inside one
# async IIFE: main drives, workers return early and only serve.
# Without the gate, a worker's fetch races close and an uncaught
# failure plus an open server hangs the loop.

test "process.isWorker is false on main":
  check runCode("process.isWorker") == "false"

test "workers serve, fetch and close":
  check runCode(
    "const http = require('std/http'); " &
    "http.serve(18120, {workers: 2}, req => 'hello workers'); " &
    "(async () => { " &
    "if (process.isWorker) return 'worker'; " &
    "const res = await http.fetch('http://127.0.0.1:18120/'); " &
    "http.close(18120); " &
    "return res.status + ':' + res.body; })()") == "200:hello workers"

test "script re-runs once per worker, identity visible":
  # Main resets + appends 'main' before spawn; the worker appends
  # 'worker' at its eval. Main polls (bounded) for both lines.
  check runCode(
    "const os = require('std/os'); " &
    "const http = require('std/http'); " &
    "const p = '/tmp/carne_test_workers_boot.txt'; " &
    "if (!process.isWorker) { " &
    "try { os.remove(p); } catch (e) {} " &
    "os.appendFile(p, 'main\\n'); } " &
    "else { os.appendFile(p, 'worker\\n'); } " &
    "http.serve(18121, {workers: 2}, req => 'w'); " &
    "(async () => { " &
    "if (process.isWorker) return 'worker'; " &
    "await http.fetch('http://127.0.0.1:18121/'); " &
    "http.close(18121); " &
    "const t0 = Date.now(); let t = ''; " &
    "while (Date.now() - t0 < 5000) { " &
    "t = os.readFile(p); " &
    "if (t.trim().split('\\n').length >= 2) break; } " &
    "os.remove(p); return t; })()") == "main\nworker\n"

test "sequential serve cycles keep serving":
  # Pipes register per serve and broadcasts fire per close; a second
  # cycle must still dispatch (regression: blocking pipe drain hung
  # the loop here).
  check runCode(
    "const http = require('std/http'); " &
    "(async () => { " &
    "http.serve(18125, req => 'one'); " &
    "const r1 = await http.get('http://127.0.0.1:18125/'); " &
    "http.close(18125); " &
    "http.serve(18126, req => 'two'); " &
    "const r2 = await http.get('http://127.0.0.1:18126/'); " &
    "http.close(18126); " &
    "return r1.body + ',' + r2.body; })()") == "one,two"

test "workers opt validates range and type":
  expect CarneError:
    discard runCode(
      "require('std/http').serve(18122, {workers: 0}, req => 'x')")
  expect CarneError:
    discard runCode(
      "require('std/http').serve(18122, {workers: 65}, req => 'x')")
  expect CarneError:
    discard runCode(
      "require('std/http').serve(18122, {workers: 'x'}, req => 'x')")

test "ws.serve throws in workers but binds on main":
  check runCode(
    "const os = require('std/os'); " &
    "const ws = require('std/ws'); " &
    "const http = require('std/http'); " &
    "const p = '/tmp/carne_test_workers_ws.txt'; " &
    "if (!process.isWorker) { try { os.remove(p); } catch (e) {} } " &
    "http.serve(18123, {workers: 2}, req => 'w'); " &
    "try { ws.serve(18124, {}); " &
    "os.appendFile(p, 'bound\\n'); } " &
    "catch (e) { os.appendFile(p, 'throw\\n'); } " &
    "(async () => { " &
    "if (process.isWorker) return 'worker'; " &
    "await http.fetch('http://127.0.0.1:18123/'); " &
    "http.close(18123); ws.close(18124); " &
    "const t0 = Date.now(); let t = ''; " &
    "while (Date.now() - t0 < 5000) { " &
    "t = os.readFile(p); " &
    "if (t.trim().split('\\n').length >= 2) break; } " &
    "os.remove(p); " &
    "return t.trim().split('\\n').sort().join(','); })()") ==
    "bound,throw"
