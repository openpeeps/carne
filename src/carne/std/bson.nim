# Carne std/bson: BSON parsing and serialization via openparser.
#
#   const bson = require("std/bson");
#   bson.parse(data)      -> value
#   bson.stringify(value) -> data
#
# Binary safety: JS strings are UTF-16 and the JSC C API is NUL-
# terminated, so raw BSON bytes travel with an opaque mapping (byte b
# becomes U+0100+b). The mapping is self-consistent: stringify output
# always parses back. Do not interpret the strings as text.

import std/json

import javascriptcore

import pkg/openparser/bson

import ../bridge

proc bytesToOpaque(s: string): string =
  ## Arbitrary bytes -> U+0100..U+01FF chars. Never contains NUL,
  ## lossless through JS strings.
  result = newStringOfCap(s.len * 2)
  for c in s:
    let b = ord(c)
    result.add(chr(0xC4 or (b shr 6)))
    result.add(chr(0x80 or (b and 0x3F)))

proc opaqueToBytes(s: string): string =
  ## Inverse of bytesToOpaque. Raises on anything outside U+0100..U+01FF.
  result = newStringOfCap(s.len div 2)
  var i = 0
  while i < s.len:
    let b = ord(s[i])
    if b >= 0xC4 and b <= 0xC7 and i + 1 < s.len and
        (ord(s[i + 1]) and 0xC0) == 0x80:
      result.add(chr(((b and 0x03) shl 6) or (ord(s[i + 1]) and 0x3F)))
      i += 2
    else:
      raise newException(CatchableError,
        "string holds text, not bson-encoded data")

## Builds the std/bson namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse:
      ## bson.parse(data) -> value
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var data: string
      if not strArg(ctx, args, 0, "parse", exception, data):
        return nil
      try:
        let raw = opaqueToBytes(data)
        var bs = newSeq[byte](raw.len)
        if raw.len > 0:
          copyMem(addr bs[0], unsafeAddr raw[0], raw.len)
        returnJson(ctx, fromBson(bs), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify:
      ## bson.stringify(value) -> data (opaque, do not read as text)
      if not checkArity(argumentCount, 1, 1, "stringify", ctx, exception):
        return nil
      var err = ""
      let node = jsToJson(ctx, args[0], err)
      if node == nil:
        throwError(ctx, "stringify: " & err, exception)
        return nil
      try:
        let bs = toBson(node)
        var raw = newString(bs.len)
        if bs.len > 0:
          copyMem(addr raw[0], unsafeAddr bs[0], bs.len)
        toJS(ctx, bytesToOpaque(raw))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
