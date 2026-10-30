# Carne std/benchmark: in-process microbenchmarking on Nim clocks.
#
#   const benchmark = require("std/benchmark");
#   benchmark.measure(() => JSON.stringify({a: 1}), {iterations: 100})
#     -> {iterations, totalMs, meanMs, medianMs, minMs, maxMs,
#         stddevMs, opsPerSec, cpuMs, rssPeak, heapDelta}
#   benchmark.compare({a: fnA, b: fnB}, {iterations: 100})
#     -> {results, ranking, fastest, speedup}
#   benchmark.now()    -> wall ms since the Unix epoch (Date.now parity)
#   benchmark.cpu()    -> process CPU ms
#   benchmark.memory() -> {rssPeak, heap} in bytes
#
# Sync functions only: the fn runs N times in a tight loop on this
# thread, so async fns would only measure body time. A throw mid-run
# propagates the original JS exception. Wall samples use the monotonic
# clock; `now()` is wall epoch for printable timestamps.
#
# Memory semantics: `rssPeak` is the getrusage high-water mark (macOS
# reports bytes), not live RSS; `heap` covers Nim-side allocations only
# (JSC's heap is invisible here). `heapDelta` forces a full collection
# before the baseline so it reads as approximate retained garbage.

import std/[algorithm, json, math, monotimes, posix, times]

import javascriptcore

import ../bridge

const
  defaultIterations = 100
  defaultWarmup = 10
  maxIterations = 1_000_000

type BenchOpts = tuple[iterations, warmup: int]

proc numField(ctx: JSContextRef; obj: JSValueRef; key: string;
    name: string; exception: ptr JSValueRef; value: var int;
    present: var bool): bool =
  ## Reads one optional numeric option. Absent/undefined keeps the
  ## default; anything non-numeric or non-integral throws.
  var err = ""
  let f = getField(ctx, obj, key, err)
  if err != "":
    throwError(ctx, name & ": options." & key & " " & err, exception)
    return false
  if f.kind == nvkUndefined:
    return true
  var n: float
  case f.kind
  of nvkInt:
    n = float(f.i)
  of nvkFloat:
    n = f.f
  else:
    throwError(ctx, name & ": options." & key & " must be a number, got `" &
      jsTypeName(f.kind) & "`", exception)
    return false
  if n != n or n != floor(n):
    throwError(ctx, name & ": options." & key & " must be an integer",
      exception)
    return false
  value = int(n)
  present = true
  true

proc benchOpts(ctx: JSContextRef; obj: JSValueRef; name: string;
    exception: ptr JSValueRef; opts: var BenchOpts): bool =
  ## Fills defaults then overlays {iterations?, warmup?}.
  opts = (iterations: defaultIterations, warmup: defaultWarmup)
  if obj == nil:
    return true
  var seenIt, seenWarm = false
  if not numField(ctx, obj, "iterations", name, exception,
      opts.iterations, seenIt):
    return false
  if not numField(ctx, obj, "warmup", name, exception,
      opts.warmup, seenWarm):
    return false
  if opts.iterations < 1:
    throwError(ctx, name & ": options.iterations must be >= 1", exception)
    return false
  if opts.iterations > maxIterations:
    throwError(ctx, name & ": options.iterations capped at " &
      $maxIterations, exception)
    return false
  if opts.warmup < 0:
    throwError(ctx, name & ": options.warmup must be >= 0", exception)
    return false
  true

proc peakRss(): int64 =
  ## Process high-water RSS in bytes (macOS getrusage unit).
  var r: Rusage
  if posix.getrusage(RUSAGE_SELF, addr r) == 0:
    int64(r.ru_maxrss)
  else:
    0

proc callFn(ctx: JSContextRef; fn: JSValueRef;
    exception: ptr JSValueRef): bool =
  ## One untimed invocation. False when the fn threw (exception set).
  var ex: JSValueRef = nil
  discard JSObjectCallAsFunction(ctx, fn, nil, 0, nil, addr ex)
  if ex != nil:
    exception[] = ex
    return false
  true

proc measureFn(ctx: JSContextRef; fn: JSValueRef; opts: BenchOpts;
    name: string; exception: ptr JSValueRef): JsonNode =
  ## Warmup (discarded), then N monotonic-timed calls. Nil on throw.
  for _ in 0 ..< opts.warmup:
    if not callFn(ctx, fn, exception):
      return nil
  GC_fullCollect()
  let heapBefore = getOccupiedMem()
  let cpuBefore = cpuTime()
  var samples = newSeq[float](opts.iterations)
  for i in 0 ..< opts.iterations:
    let t0 = getMonoTime()
    var ex: JSValueRef = nil
    discard JSObjectCallAsFunction(ctx, fn, nil, 0, nil, addr ex)
    samples[i] = float((getMonoTime() - t0).inNanoseconds) / 1e6
    if ex != nil:
      exception[] = ex
      return nil
  let cpuMs = (cpuTime() - cpuBefore) * 1000.0
  let heapDelta = getOccupiedMem() - heapBefore
  var total = 0.0
  var lo = samples[0]
  var hi = samples[0]
  for s in samples:
    total += s
    if s < lo:
      lo = s
    if s > hi:
      hi = s
  let mean = total / float(opts.iterations)
  var variance = 0.0
  for s in samples:
    variance += (s - mean) * (s - mean)
  variance /= float(opts.iterations)
  sort(samples)
  let mid = opts.iterations div 2
  let median =
    if opts.iterations mod 2 == 1:
      samples[mid]
    else:
      (samples[mid - 1] + samples[mid]) / 2.0
  result = newJObject()
  result["iterations"] = %opts.iterations
  result["totalMs"] = %total
  result["meanMs"] = %mean
  result["medianMs"] = %median
  result["minMs"] = %lo
  result["maxMs"] = %hi
  result["stddevMs"] = %sqrt(variance)
  result["opsPerSec"] =
    if total > 0.0: %(float(opts.iterations) / (total / 1000.0))
    else: %0.0
  result["cpuMs"] = %cpuMs
  result["rssPeak"] = %peakRss()
  result["heapDelta"] = %heapDelta

## Builds the std/benchmark namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn measure(fn: NimValue, opts ?: JSObjectRef):
      ## benchmark.measure(fn[, {iterations, warmup}]) -> stats object
      if fn.kind != nvkFunction:
        throwTypeMismatch(ctx, "measure", "fn", jsTypeName(fn.kind),
          "function", docBlock, exception)
        return nil
      var o: BenchOpts
      if not benchOpts(ctx, opts, "measure", exception, o):
        return nil
      let st = measureFn(ctx, fn.raw, o, "measure", exception)
      if st == nil:
        return nil
      returnJson(ctx, st, "measure", exception)

    module.registerFn compare(fns: JSObjectRef, opts ?: JSObjectRef):
      ## benchmark.compare({name: fn}[, {iterations, warmup}])
      ##   -> {results, ranking, fastest, speedup}
      var o: BenchOpts
      if not benchOpts(ctx, opts, "compare", exception, o):
        return nil
      let names = JSObjectCopyPropertyNames(ctx, fns)
      if names == nil:
        throwError(ctx, "compare: cannot read functions object", exception)
        return nil
      defer: JSPropertyNameArrayRelease(names)
      let count = int(JSPropertyNameArrayGetCount(names))
      if count == 0:
        throwError(ctx, "compare: needs at least one function", exception)
        return nil
      var results = newJObject()
      var means = newJObject()
      for idx in 0 ..< count:
        let jsName =
          JSPropertyNameArrayGetNameAtIndex(names, csize_t(idx))
        let key = $jsName
        var err = ""
        let fv = getField(ctx, fns, key, err)
        if err != "":
          throwError(ctx, "compare: \"" & key & "\" " & err, exception)
          return nil
        if fv.kind != nvkFunction:
          throwError(ctx, "compare: \"" & key & "\" must be a function, " &
            "got `" & jsTypeName(fv.kind) & "`", exception)
          return nil
        let st = measureFn(ctx, fv.raw, o, "compare", exception)
        if st == nil:
          return nil
        results[key] = st
        means[key] = st["meanMs"]
      var order: seq[string] = @[]
      for k in means.keys:
        order.add(k)
      sort(order, proc(a, b: string): int =
        cmp(means[a].getFloat(), means[b].getFloat()))
      let slowest = means[order[^1]].getFloat()
      var rank = newJArray()
      var speedup = newJObject()
      for k in order:
        rank.add(%k)
        speedup[k] =
          if slowest > 0.0: %(slowest / means[k].getFloat())
          else: %1.0
      var resp = newJObject()
      resp["results"] = results
      resp["ranking"] = rank
      resp["fastest"] = %order[0]
      resp["speedup"] = speedup
      returnJson(ctx, resp, "compare", exception)

    module.registerFn now():
      ## benchmark.now() -> wall ms since the Unix epoch
      toJS(ctx, getTime().toUnixFloat() * 1000.0)

    module.registerFn cpu():
      ## benchmark.cpu() -> process CPU ms
      toJS(ctx, cpuTime() * 1000.0)

    module.registerFn memory():
      ## benchmark.memory() -> {rssPeak, heap} in bytes
      var mem = newJObject()
      mem["rssPeak"] = %peakRss()
      mem["heap"] = %getOccupiedMem()
      returnJson(ctx, mem, "memory", exception)
