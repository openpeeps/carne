# Carne std/diff: unified diffs via openparser (Myers/patience/histogram).
#
#   const diff = require("std/diff");
#   diff.diff("a\nb\n", "a\nc\n")
#     -> {identical: false, stats: {added, removed, ...}, hunks: [...]}
#   diff.unified("a\nb\n", "a\nc\n")
#     -> "--- a\n+++ b\n@@ -1,2 +1,2 @@\n a\n-b\n+c\n"
#
# Hunk lines are {kind: "equal"|"insert"|"delete", text, spans?};
# spans are intra-line changed byte ranges for highlighting. Both
# functions take an optional {context} options object (default 3).

import std/[math, strutils]

import javascriptcore

import pkg/openparser/diff

import ../bridge

proc readOpts(ctx: JSContextRef; obj: JSValueRef;
    name: string; exception: ptr JSValueRef;
    opts: var DiffOptions; docBlock = ""): bool =
  ## Reads {context?} lazily; absent and undefined both mean default.
  template oerr(msg: string): untyped =
    throwError(ctx,
      (if docBlock.len > 0: docBlock & "\n" else: "") & msg, exception)
  opts = DiffOptions()
  if obj == nil:
    return true
  var err = ""
  let f = getField(ctx, obj, "context", err)
  if err != "":
    oerr(name & ": options.context " & err)
    return false
  var c = DiffContext
  case f.kind
  of nvkUndefined:
    return true
  of nvkInt:
    c = int(f.i)
  of nvkFloat:
    if f.f != trunc(f.f):
      oerr(name & ": options.context must be an integer")
      return false
    c = int(f.f)
  else:
    oerr(name & ": options.context must be an integer")
    return false
  if c < -1:
    oerr(name & ": options.context must be >= -1")
    return false
  opts.context = c
  true

proc diffToJS(ctx: JSContextRef; d: Diff; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  ## Diff -> live JS value, no JsonNode middle layer.
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "identical", toJS(ctx, isIdentical(d)),
      fname, exception):
    return nil
  if not setPropChecked(ctx, obj, "binary", toJS(ctx, d.binary),
      fname, exception):
    return nil
  if not setPropChecked(ctx, obj, "truncated", toJS(ctx, d.truncated),
      fname, exception):
    return nil
  let stats = newObject(ctx)
  if not setPropChecked(ctx, stats, "added", toJS(ctx, d.stats.added),
      fname, exception):
    return nil
  if not setPropChecked(ctx, stats, "removed", toJS(ctx, d.stats.removed),
      fname, exception):
    return nil
  if not setPropChecked(ctx, stats, "changed", toJS(ctx, d.stats.changed),
      fname, exception):
    return nil
  if not setPropChecked(ctx, stats, "hunks", toJS(ctx, d.stats.hunkCount),
      fname, exception):
    return nil
  if not setPropChecked(ctx, stats, "bytesAdded",
      toJS(ctx, d.stats.bytesAdded), fname, exception):
    return nil
  if not setPropChecked(ctx, stats, "bytesRemoved",
      toJS(ctx, d.stats.bytesRemoved), fname, exception):
    return nil
  if not setPropChecked(ctx, obj, "stats", stats, fname, exception):
    return nil
  var hunkVals: seq[JSValueRef] = @[]
  for h in d.hunks:
    let hobj = newObject(ctx)
    if not setPropChecked(ctx, hobj, "header",
        toJS(ctx, renderHunkHeader(h).strip()), fname, exception):
      return nil
    var lineVals: seq[JSValueRef] = @[]
    for line in h.lines:
      let ln = newObject(ctx)
      if not setPropChecked(ctx, ln, "kind", toJS(ctx, $line.kind),
          fname, exception):
        return nil
      let isA = line.kind == dlDelete
      if not setPropChecked(ctx, ln, "text",
          toJS(ctx, contentText(if isA: d.a.view else: d.b.view, line,
            isA)), fname, exception):
        return nil
      if line.spans.len > 0:
        var spanVals: seq[JSValueRef] = @[]
        for s in line.spans:
          let sp = newObject(ctx)
          if not setPropChecked(ctx, sp, "start", toJS(ctx, s.start),
              fname, exception):
            return nil
          if not setPropChecked(ctx, sp, "stop", toJS(ctx, s.stop),
              fname, exception):
            return nil
          spanVals.add(sp)
        var spEx: JSValueRef = nil
        let spans = JSObjectMakeArray(ctx, csize_t(spanVals.len),
          addr spanVals[0], addr spEx)
        if spEx != nil:
          throwError(ctx, fname & ": could not convert result to JS",
            exception)
          return nil
        if not setPropChecked(ctx, ln, "spans", spans, fname, exception):
          return nil
      lineVals.add(ln)
    var lnEx: JSValueRef = nil
    let lines =
      if lineVals.len > 0:
        JSObjectMakeArray(ctx, csize_t(lineVals.len), addr lineVals[0],
          addr lnEx)
      else:
        JSObjectMakeArray(ctx, 0, nil, addr lnEx)
    if lnEx != nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, hobj, "lines", lines, fname, exception):
      return nil
    hunkVals.add(hobj)
  var hEx: JSValueRef = nil
  let hunks =
    if hunkVals.len > 0:
      JSObjectMakeArray(ctx, csize_t(hunkVals.len), addr hunkVals[0],
        addr hEx)
    else:
      JSObjectMakeArray(ctx, 0, nil, addr hEx)
  if hEx != nil:
    throwError(ctx, fname & ": could not convert result to JS", exception)
    return nil
  if not setPropChecked(ctx, obj, "hunks", hunks, fname, exception):
    return nil
  result = obj

## Builds the std/diff namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn diff(a: string, b: string,
        optsObj ?: JSObjectRef):
      ## diff.diff(a, b[, {context}]) -> {identical, stats, hunks}
      var opts: DiffOptions
      if optsObj != nil:
        if not readOpts(ctx, optsObj, "diff", exception, opts, docBlock):
          return nil
      else:
        opts = DiffOptions()
      try:
        let j = diffToJS(ctx, diff(a, b, opts), "diff", exception)
        if j == nil:
          throwError(ctx, "diff: could not convert result to JS",
            exception)
          return nil
        j
      except CatchableError as e:
        throwError(ctx, "diff: " & e.msg, exception)
        nil

    module.registerFn unified(a: string, b: string,
        optsObj ?: JSObjectRef):
      ## diff.unified(a, b[, {context}]) -> unified diff text
      var opts: DiffOptions
      if optsObj != nil:
        if not readOpts(ctx, optsObj, "unified", exception, opts, docBlock):
          return nil
      else:
        opts = DiffOptions()
      try:
        toJS(ctx, renderUnified(diff(a, b, opts), opts))
      except CatchableError as e:
        throwError(ctx, "unified: " & e.msg, exception)
        nil
