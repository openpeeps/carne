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

import std/[json, math, strutils]

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

proc diffToJson(d: Diff): JsonNode =
  result = newJObject()
  result["identical"] = %isIdentical(d)
  result["binary"] = %d.binary
  result["truncated"] = %d.truncated
  result["stats"] = %*{"added": d.stats.added, "removed": d.stats.removed,
    "changed": d.stats.changed, "hunks": d.stats.hunkCount,
    "bytesAdded": d.stats.bytesAdded, "bytesRemoved": d.stats.bytesRemoved}
  var hunks = newJArray()
  for h in d.hunks:
    var obj = newJObject()
    obj["header"] = %renderHunkHeader(h).strip()
    var lines = newJArray()
    for line in h.lines:
      var ln = newJObject()
      ln["kind"] = % $line.kind
      let isA = line.kind == dlDelete
      ln["text"] = %contentText(if isA: d.a.view else: d.b.view, line, isA)
      if line.spans.len > 0:
        var spans = newJArray()
        for s in line.spans:
          spans.add(%*{"start": s.start, "stop": s.stop})
        ln["spans"] = spans
      lines.add(ln)
    obj["lines"] = lines
    hunks.add(obj)
  result["hunks"] = hunks

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
        returnJson(ctx, diffToJson(diff(a, b, opts)), "diff", exception)
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
