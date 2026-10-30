# Carne std/qr: QR code generation via openparser (Model 2).
#
#   const qr = require("std/qr");
#   qr.encode("hello")
#     -> {size: 21, svg: "<svg ...>...", terminal: "██▄..."}
#   qr.encode("hello", {ecLevel: "H"}) -> higher error correction
#
# ecLevel is one of L/M/Q/H (default M). Decoding needs image input
# and is out of scope in v1.

import std/[json, strutils]

import javascriptcore

import pkg/openparser/qr/model2
import pkg/openparser/qr/render

import ../bridge

proc ecLevelArg(ctx: JSContextRef; obj: JSValueRef;
    name: string): QrEcLevel =
  ## Reads {ecLevel?} lazily; absent and undefined both mean default.
  ## Raises on anything else.
  result = ecMedium
  if obj == nil:
    return
  var err = ""
  let f = getField(ctx, obj, "ecLevel", err)
  if err != "":
    raise newException(CatchableError, name & ": options.ecLevel " & err)
  if f.kind == nvkUndefined:
    return
  if f.kind != nvkString:
    raise newException(CatchableError,
      name & ": options.ecLevel must be one of L, M, Q, H")
  case f.s.toUpperAscii()
  of "L":
    result = ecLow
  of "M":
    result = ecMedium
  of "Q":
    result = ecQuartile
  of "H":
    result = ecHigh
  else:
    raise newException(CatchableError,
      name & ": options.ecLevel must be one of L, M, Q, H")

## Builds the std/qr namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn encode(text: string, optsObj ?: JSObjectRef):
      ## qr.encode(text[, {ecLevel}]) -> {size, svg, terminal}
      var level = ecMedium
      if optsObj != nil:
        try:
          level = ecLevelArg(ctx, optsObj, "encode")
        except CatchableError as e:
          throwError(ctx, e.msg, exception)
          return nil
      try:
        var opts = defaultQrEncodeOptions()
        opts.ecLevel = level
        let m = encodeQr(text, opts)
        returnJson(ctx, %*{"size": m.width, "svg": toSvg(m),
          "terminal": toTerminal(m)}, "encode", exception)
      except CatchableError as e:
        throwError(ctx, "encode: " & e.msg, exception)
        nil
