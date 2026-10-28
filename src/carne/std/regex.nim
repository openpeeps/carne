# Carne std/regex: globals-free regular expressions via openparser.
#
# JS already has RegExp; this exists for server-side parity with Nim
# code using openparser (same engine, same semantics):
#
#   const regex = require("std/regex");
#   regex.test("\\d+", "abc123")       -> true (search, like RegExp.test)
#   regex.exec("(\\w+)@(\\w+)", "mail ada@x.io")
#     -> {match: "ada@x", index: 5, groups: ["ada", "x"]}
#   regex.matchAll("a+", "aa b aaa")  -> [{match: "aa", ...}, ...]
#
# exec returns null on no match. Non-participating groups are null.
# index is a JS string index (the engine works on UTF-8 bytes; the
# offset is converted, so astral characters count as 2 like JS).

import std/json

import javascriptcore

import pkg/openparser/regex/vm

import ../bridge

proc utf16Index(s: string; bytePos: int): int =
  ## Converts a UTF-8 byte offset to a JS (UTF-16) string index.
  var i = 0
  let n = min(bytePos, s.len)
  while i < n:
    let b = ord(s[i])
    var cp, l: int
    if b < 0x80:
      cp = b
      l = 1
    elif b < 0xE0:
      cp = b and 0x1F
      l = 2
    elif b < 0xF0:
      cp = b and 0x0F
      l = 3
    else:
      cp = b and 0x07
      l = 4
    var k = 1
    while k < l and i + k < s.len:
      cp = (cp shl 6) or (ord(s[i + k]) and 0x3F)
      inc k
    if cp > 0xFFFF:
      inc result, 2
    else:
      inc result
    i += l

proc matchToJson(text: string; m: MatchResult): JsonNode =
  result = newJObject()
  result["match"] = %text[m.start ..< m.stop]
  result["index"] = %utf16Index(text, m.start)
  var groups = newJArray()
  var i = 0
  while i + 1 < m.captures.len:
    let a = m.captures[i]
    let b = m.captures[i + 1]
    if a < 0 or b < 0:
      groups.add(newJNull())
    else:
      groups.add(%text[a ..< b])
    i += 2
  result["groups"] = groups

## Builds the std/regex namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn test:
      ## regex.test(pattern, text) -> bool (search semantics)
      if not checkArity(argumentCount, 2, 2, "test", ctx, exception):
        return nil
      var pattern, text: string
      if not strArg(ctx, args, 0, "test", exception, pattern):
        return nil
      if not strArg(ctx, args, 1, "test", exception, text):
        return nil
      try:
        toJS(ctx, find(pattern, text).matched)
      except CatchableError as e:
        throwError(ctx, "test: " & e.msg, exception)
        nil

    module.registerFn exec:
      ## regex.exec(pattern, text) -> {match, index, groups} | null
      if not checkArity(argumentCount, 2, 2, "exec", ctx, exception):
        return nil
      var pattern, text: string
      if not strArg(ctx, args, 0, "exec", exception, pattern):
        return nil
      if not strArg(ctx, args, 1, "exec", exception, text):
        return nil
      try:
        let m = find(pattern, text)
        if not m.matched:
          returnJson(ctx, newJNull(), "exec", exception)
        else:
          returnJson(ctx, matchToJson(text, m), "exec", exception)
      except CatchableError as e:
        throwError(ctx, "exec: " & e.msg, exception)
        nil

    module.registerFn matchAll:
      ## regex.matchAll(pattern, text) -> [{match, index, groups}]
      if not checkArity(argumentCount, 2, 2, "matchAll", ctx, exception):
        return nil
      var pattern, text: string
      if not strArg(ctx, args, 0, "matchAll", exception, pattern):
        return nil
      if not strArg(ctx, args, 1, "matchAll", exception, text):
        return nil
      try:
        var arr = newJArray()
        for m in findAll(pattern, text):
          arr.add(matchToJson(text, m))
        returnJson(ctx, arr, "matchAll", exception)
      except CatchableError as e:
        throwError(ctx, "matchAll: " & e.msg, exception)
        nil
