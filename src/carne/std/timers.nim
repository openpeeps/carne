# Carne timers: Node-style globals backed by the powpow event loop.
#
#   setTimeout(fn, ms, ...args)   -> numeric id
#   setInterval(fn, ms, ...args)  -> numeric id
#   clearTimeout(id) / clearInterval(id)
#
# Callbacks are protected from GC until they fire or are cleared.
# Each live timer holds one pending-work slot; the run drains until
# none remain. Timer throws are recorded as uncaught (exit 1 after
# drain) without killing the remaining timers.

import std/tables

import javascriptcore

import powpow/loop

import ../bridge

proc decPending(rt: Runtime) =
  dec rt.pending
  if rt.pending <= 0 and not rt.exitRequested:
    rt.pending = 0
    rt.loop.stop()

proc releaseTimer(rt: Runtime; entry: TimerEntry) =
  JSValueUnprotect(rt.ctx, entry.fn)
  for v in entry.rest:
    JSValueUnprotect(rt.ctx, v)

proc fireTimer(rt: Runtime; jsId: int) =
  ## Runs one timer callback inside JS. Runs on the loop thread,
  ## which is the same thread that owns the JS context.
  if not rt.timers.hasKey(jsId):
    return # cleared before firing
  let entry = rt.timers[jsId]
  var ex: JSValueRef = nil
  let res =
    if entry.rest.len > 0:
      var vals = entry.rest
      JSObjectCallAsFunction(rt.ctx, entry.fn, nil, csize_t(vals.len),
        addr vals[0], addr ex)
    else:
      JSObjectCallAsFunction(rt.ctx, entry.fn, nil, 0, nil, addr ex)
  discard res
  if ex != nil:
    if rt.uncaught.len == 0:
      rt.uncaught = valueToString(rt.ctx, ex)
    rt.exitCode = 1
  if not entry.isInterval:
    rt.timers.del(jsId)
    releaseTimer(rt, entry)
    decPending(rt)

proc scheduleTimer(ctx: JSContextRef; function: JSObjectRef;
    argumentCount: csize_t; arguments: ptr JSValueRef;
    exception: ptr JSValueRef; name: string;
    isInterval: bool): JSValueRef {.cdecl.} =
  if int(argumentCount) < 2:
    throwError(ctx, name & ": expected at least 2 argument(s), got " &
      $int(argumentCount), exception)
    return nil
  let args = cast[ptr UncheckedArray[JSValueRef]](arguments)
  var fnVal: NimValue
  if not nimArg(ctx, args, 0, name, exception, fnVal):
    return nil
  if fnVal.kind != nvkFunction:
    throwError(ctx, name & ": first argument is not a function, got " &
      jsTypeName(fnVal.kind), exception)
    return nil
  var delay = 0.0
  if not numArg(ctx, args, 1, name, exception, delay):
    return nil
  var delayMs = int(delay)
  if delay != delay or delayMs < 0:
    delayMs = 0
  let rt = currentRt()
  let fn = args[0]
  var rest: seq[JSValueRef] = @[]
  for i in 2 ..< int(argumentCount):
    rest.add(args[i])
  JSValueProtect(ctx, fn)
  for v in rest:
    JSValueProtect(ctx, v)
  inc rt.timerSeq
  let jsId = rt.timerSeq
  let loop = rt.ensureLoop()
  inc rt.pending
  let timerId =
    if isInterval:
      loop.addInterval(delayMs, proc(id: int) = fireTimer(rt, jsId))
    else:
      loop.addTimer(delayMs, proc(id: int) = fireTimer(rt, jsId))
  rt.timers[jsId] = TimerEntry(id: timerId, fn: fn, rest: rest,
    isInterval: isInterval)
  toJS(ctx, jsId)

proc setTimeoutImpl(ctx: JSContextRef; function, thisObject: JSObjectRef;
    argumentCount: csize_t; arguments: ptr JSValueRef;
    exception: ptr JSValueRef): JSValueRef {.cdecl.} =
  scheduleTimer(ctx, function, argumentCount, arguments, exception,
    "setTimeout", false)

proc setIntervalImpl(ctx: JSContextRef; function, thisObject: JSObjectRef;
    argumentCount: csize_t; arguments: ptr JSValueRef;
    exception: ptr JSValueRef): JSValueRef {.cdecl.} =
  scheduleTimer(ctx, function, argumentCount, arguments, exception,
    "setInterval", true)

proc clearTimerImpl(ctx: JSContextRef; function, thisObject: JSObjectRef;
    argumentCount: csize_t; arguments: ptr JSValueRef;
    exception: ptr JSValueRef): JSValueRef {.cdecl.} =
  ## Implements both clearTimeout and clearInterval. Unknown ids are no-ops.
  if int(argumentCount) > 0 and arguments != nil:
    let args = cast[ptr UncheckedArray[JSValueRef]](arguments)
    var ex: JSValueRef = nil
    let idNum = JSValueToNumber(ctx, args[0], addr ex)
    if ex == nil:
      let rt = currentRt()
      let jsId = int(idNum)
      if rt.timers.hasKey(jsId):
        let entry = rt.timers[jsId]
        rt.ensureLoop().cancelTimer(entry.id)
        rt.timers.del(jsId)
        releaseTimer(rt, entry)
        decPending(rt)
  JSValueMakeUndefined(ctx)

proc installTimers*(rt: Runtime; setupEx: ptr JSValueRef) =
  ## Installs the timer globals.
  let global = JSContextGetGlobalObject(rt.ctx)
  setProp(rt.ctx, global, "setTimeout",
    makeFunction(rt.ctx, "setTimeout", setTimeoutImpl), setupEx)
  setProp(rt.ctx, global, "setInterval",
    makeFunction(rt.ctx, "setInterval", setIntervalImpl), setupEx)
  setProp(rt.ctx, global, "clearTimeout",
    makeFunction(rt.ctx, "clearTimeout", clearTimerImpl), setupEx)
  setProp(rt.ctx, global, "clearInterval",
    makeFunction(rt.ctx, "clearInterval", clearTimerImpl), setupEx)
