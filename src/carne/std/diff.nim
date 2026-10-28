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

import std/[json, strutils]

import javascriptcore

import pkg/openparser/diff

import ../bridge

proc readOpts(ctx: JSContextRef; args: ptr UncheckedArray[JSValueRef];
    n: int; name: string; exception: ptr JSValueRef;
    opts: var DiffOptions): bool =
  opts = DiffOptions()
  var err = ""
  let node = jsToJson(ctx, args[n], err)
  if node == nil:
    throwError(ctx, name & ": options " & err, exception)
    return false
  if node.kind != JObject:
    throwError(ctx, name & ": options must be an object", exception)
    return false
  if node.hasKey("context"):
    if node["context"].kind != JInt:
      throwError(ctx, name & ": options.context must be an integer",
        exception)
      return false
    let c = node["context"].getInt()
    if c < -1:
      throwError(ctx, name & ": options.context must be >= -1", exception)
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

    module.registerFn diff:
      ## diff.diff(a, b[, {context}]) -> {identical, stats, hunks}
      if not checkArity(argumentCount, 2, 3, "diff", ctx, exception):
        return nil
      var a, b: string
      if not strArg(ctx, args, 0, "diff", exception, a):
        return nil
      if not strArg(ctx, args, 1, "diff", exception, b):
        return nil
      var opts: DiffOptions
      if int(argumentCount) == 3:
        if not readOpts(ctx, args, 2, "diff", exception, opts):
          return nil
      else:
        opts = DiffOptions()
      try:
        returnJson(ctx, diffToJson(diff(a, b, opts)), "diff", exception)
      except CatchableError as e:
        throwError(ctx, "diff: " & e.msg, exception)
        nil

    module.registerFn unified:
      ## diff.unified(a, b[, {context}]) -> unified diff text
      if not checkArity(argumentCount, 2, 3, "unified", ctx, exception):
        return nil
      var a, b: string
      if not strArg(ctx, args, 0, "unified", exception, a):
        return nil
      if not strArg(ctx, args, 1, "unified", exception, b):
        return nil
      var opts: DiffOptions
      if int(argumentCount) == 3:
        if not readOpts(ctx, args, 2, "unified", exception, opts):
          return nil
      else:
        opts = DiffOptions()
      try:
        toJS(ctx, renderUnified(diff(a, b, opts), opts))
      except CatchableError as e:
        throwError(ctx, "unified: " & e.msg, exception)
        nil
