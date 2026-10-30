# Carne std/env: process environment access.
#
#   const env = require("std/env");
#   env.args()        -> process.argv as a fresh array
#   env.getenv("HOME") -> string | undefined
#   env.cwd()         -> string
#   env.exit(2)       -> terminates the run with exit code 2

import std/os

import javascriptcore

# Narrow import: a full `import powpow/loop` re-exports `init`, which
# would shadow bridge's `init` macro in overload resolution.
from powpow/loop import stop

import ../bridge

init proc(module: Module) =
  ## Builds the std/env namespace object.
  exportObject:

    module.registerFn args():
      ## env.args() -> process.argv as a fresh array
      let rt = currentRt()
      var vals: seq[JSValueRef] = @[]
      for arg in rt.argv:
        vals.add(toJS(ctx, arg))
      var ex: JSValueRef = nil
      let arr =
        if vals.len > 0:
          JSObjectMakeArray(ctx, csize_t(vals.len), addr vals[0], addr ex)
        else:
          JSObjectMakeArray(ctx, 0, nil, addr ex)
      if arr == nil:
        if ex != nil and exception != nil:
          exception[] = ex
        return nil
      arr

    module.registerFn getenv(key: string):
      ## env.getenv("HOME") -> string | undefined
      if not existsEnv(key):
        return JSValueMakeUndefined(ctx)
      toJS(ctx, getEnv(key))

    module.registerFn cwd():
      ## env.cwd() -> string
      try:
        toJS(ctx, getCurrentDir())
      except OSError as e:
        throwError(ctx, "cwd: " & e.msg, exception)
        nil

    module.registerFn exit(code ?: float):
      ## env.exit(2) -> terminates the run with exit code 2
      let rt = currentRt()
      rt.exitCode = int(code)
      rt.exitRequested = true
      if rt.loop != nil:
        rt.loop.stop()
      JSValueMakeUndefined(ctx)
