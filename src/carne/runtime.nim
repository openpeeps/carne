# Carne runtime: owns the JS context and the powpow event loop.
#
# Installs console.log (+ print alias), process.argv, global require and
# the timer globals, evaluates the script, then drains the loop while
# async work remains. macOS only (system JavaScriptCore).

import std/strutils
import std/tables

import javascriptcore

import powpow/loop

import ./bridge
import ./modules
import ./std/timers

export bridge

proc consoleLogImpl(ctx: JSContextRef; function, thisObject: JSObjectRef;
    argumentCount: csize_t; arguments: ptr JSValueRef;
    exception: ptr JSValueRef): JSValueRef {.cdecl.} =
  ## Implements console.log / print: joins args with spaces on stdout.
  var parts: seq[string] = @[]
  if argumentCount > 0 and arguments != nil:
    let args = cast[ptr UncheckedArray[JSValueRef]](arguments)
    for i in 0 ..< int(argumentCount):
      var ex: JSValueRef = nil
      let s = JSValueToStringCopy(ctx, args[i], addr ex)
      if s == nil:
        if ex != nil and exception != nil:
          exception[] = ex
        return nil
      let text = $s
      JSStringRelease(s)
      parts.add(text)
  echo parts.join(" ")
  JSValueMakeUndefined(ctx)

proc installConsole(ctx: JSContextRef; setupEx: ptr JSValueRef) =
  ## Installs global `console.log` and a `print` alias.
  let global = JSContextGetGlobalObject(ctx)
  let logFn = makeFunction(ctx, "log", consoleLogImpl)
  let consoleObj = newObject(ctx)
  setProp(ctx, consoleObj, "log", logFn, setupEx)
  setProp(ctx, global, "console", consoleObj, setupEx)
  setProp(ctx, global, "print", logFn, setupEx)

proc installProcess(ctx: JSContextRef; argv: seq[string];
    setupEx: ptr JSValueRef) =
  ## Installs global `process.argv` from the given Nim strings.
  let global = JSContextGetGlobalObject(ctx)
  var vals: seq[JSValueRef] = @[]
  for arg in argv:
    vals.add(toJS(ctx, arg))
  var ex: JSValueRef = nil
  let arr =
    if vals.len > 0:
      JSObjectMakeArray(ctx, csize_t(vals.len), addr vals[0], addr ex)
    else:
      JSObjectMakeArray(ctx, 0, nil, addr ex)
  let processObj = newObject(ctx)
  setProp(ctx, processObj, "argv", arr, setupEx)
  setProp(ctx, global, "process", processObj, setupEx)

proc runCodeEx*(code: string; sourceURL = "script.js";
    argv: seq[string] = @[]): tuple[output: string, code: int] =
  ## Evaluates `code`, drains async work, returns the completion value
  ## ("" for undefined) and the process exit code. Raises CarneError on
  ## JS exceptions (eval-time or uncaught async).
  let loop = newLoop()
  let rt = Runtime(ctx: nil, argv: argv, loop: loop, pending: 0,
    exitRequested: false, exitCode: 0, uncaught: "",
    instances: initTable[string, JSObjectRef](), timerSeq: 0,
    timers: initTable[int, TimerEntry]())
  withGlobalContext(ctx):
    rt.ctx = ctx
    setCurrentRt(rt)
    try:
      var setupEx: JSValueRef = nil
      installConsole(ctx, addr setupEx)
      installProcess(ctx, argv, addr setupEx)
      installRequire(rt, addr setupEx)
      installTimers(rt, addr setupEx)
      if setupEx != nil:
        raise newException(CarneError,
          "failed to initialize runtime: " & valueToString(ctx, setupEx))
      var ex: JSValueRef = nil
      let res = evalScript(ctx, code, sourceURL = sourceURL, exception = ex)
      if ex != nil:
        raise newException(CarneError, valueToString(ctx, ex))
      var completion = ""
      if res != nil and not JSValueIsUndefined(ctx, res):
        completion = valueToString(ctx, res)
      if not rt.exitRequested and rt.pending > 0:
        loop.run()
      if rt.uncaught.len > 0:
        raise newException(CarneError, rt.uncaught)
      return (completion, rt.exitCode)
    finally:
      setCurrentRt(nil)
      loop.close()

proc runCode*(code: string; sourceURL = "script.js";
    argv: seq[string] = @[]): string =
  ## Evaluates `code`, returns the completion value as a string.
  ## Empty string for undefined results. Raises CarneError on JS exceptions.
  runCodeEx(code, sourceURL, argv).output

proc runFileEx*(path: string;
    extraArgs: seq[string] = @[]): tuple[output: string, code: int] =
  ## Reads `path` and evaluates it. process.argv is
  ## ["carne", path, extraArgs...]. Raises CarneError / IOError.
  let code = readFile(path)
  let argv = @["carne", path] & extraArgs
  runCodeEx(code, sourceURL = path, argv = argv)

proc runFile*(path: string; extraArgs: seq[string] = @[]): string =
  ## Reads `path` and evaluates it. Raises CarneError / IOError.
  runFileEx(path, extraArgs).output
