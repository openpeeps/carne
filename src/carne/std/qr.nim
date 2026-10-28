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

proc ecLevelArg(node: JsonNode; name: string): QrEcLevel =
  ## Reads {ecLevel} from an options object. Raises on anything else.
  result = ecMedium
  if node == nil:
    return
  if node.kind != JObject:
    raise newException(CatchableError, name & ": options must be an object")
  if node.hasKey("ecLevel"):
    if node["ecLevel"].kind != JString:
      raise newException(CatchableError,
        name & ": options.ecLevel must be one of L, M, Q, H")
    case node["ecLevel"].getStr().toUpperAscii()
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

    module.registerFn encode:
      ## qr.encode(text[, {ecLevel}]) -> {size, svg, terminal}
      if not checkArity(argumentCount, 1, 2, "encode", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "encode", exception, text):
        return nil
      var level = ecMedium
      if int(argumentCount) == 2:
        var err = ""
        let node = jsToJson(ctx, args[1], err)
        if node == nil:
          throwError(ctx, "encode: options " & err, exception)
          return nil
        try:
          level = ecLevelArg(node, "encode")
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
