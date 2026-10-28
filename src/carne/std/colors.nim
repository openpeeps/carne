# Carne std/colors: color parsing, formatting and math via openparser.
#
# Colors cross the boundary as {r, g, b, a} objects (r/g/b 0..255
# integers, a 0..1):
#
#   const colors = require("std/colors");
#   colors.parse("red")             -> {r: 255, g: 0, b: 0, a: 1}
#   colors.toHex(colors.parse("red")) -> "#ff0000"
#   colors.lighten(colors.parse("#333"), 20) -> {r, g, b, a}
#   colors.contrastRatio(a, b)      -> 1..21
#
# Accepts anything parseColor does: hex, rgb()/hsl()/hsv()/cmyk()/
# lab()/lch()/oklab()/oklch() strings and named colors.

import std/[json, math]

import javascriptcore

import pkg/openparser/colors

import ../bridge

proc colorToJson(c: Color): JsonNode =
  %*{"r": int(round(c.r * 255.0)), "g": int(round(c.g * 255.0)),
    "b": int(round(c.b * 255.0)), "a": c.a}

proc numField(node: JsonNode; field: string): float =
  ## Reads a numeric field as float. Raises on anything else.
  if not node.hasKey(field):
    raise newException(CatchableError, "color needs numeric \"" & field & "\"")
  case node[field].kind
  of JInt:
    float(node[field].getInt())
  of JFloat:
    node[field].getFloat()
  else:
    raise newException(CatchableError, "color needs numeric \"" & field & "\"")

proc colorArg(ctx: JSContextRef; args: ptr UncheckedArray[JSValueRef];
    i: int; name: string; exception: ptr JSValueRef;
    color: var Color): bool =
  ## Reads arg i as a {r, g, b, a?} object. False + JS throw on failure.
  var err = ""
  let node = jsToJson(ctx, args[i], err)
  if node == nil:
    throwError(ctx, name & ": color " & err, exception)
    return false
  if node.kind != JObject:
    throwError(ctx, name & ": color must be an {r, g, b, a?} object",
      exception)
    return false
  try:
    var c = Color(a: 1.0)
    c.r = numField(node, "r") / 255.0
    c.g = numField(node, "g") / 255.0
    c.b = numField(node, "b") / 255.0
    if node.hasKey("a"):
      c.a = numField(node, "a")
    if c.r < 0.0 or c.r > 1.0 or c.g < 0.0 or c.g > 1.0 or
        c.b < 0.0 or c.b > 1.0 or c.a < 0.0 or c.a > 1.0:
      throwError(ctx, name & ": r/g/b must be 0..255 and a 0..1", exception)
      return false
    color = c
    true
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg, exception)
    false

proc amountArg(ctx: JSContextRef; args: ptr UncheckedArray[JSValueRef];
    i: int; name: string; exception: ptr JSValueRef;
    amount: var float): bool =
  if not numArg(ctx, args, i, name, exception, amount):
    return false
  true

## Builds the std/colors namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse:
      ## colors.parse(text) -> {r, g, b, a}
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      try:
        returnJson(ctx, colorToJson(parseColor(text)), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn random:
      ## colors.random() -> {r, g, b, a}
      if not checkArity(argumentCount, 0, 0, "random", ctx, exception):
        return nil
      try:
        returnJson(ctx, colorToJson(randomColor()), "random", exception)
      except CatchableError as e:
        throwError(ctx, "random: " & e.msg, exception)
        nil

    module.registerFn toHex:
      ## colors.toHex(color) -> "#rrggbb"
      if not checkArity(argumentCount, 1, 1, "toHex", ctx, exception):
        return nil
      var c: Color
      if not colorArg(ctx, args, 0, "toHex", exception, c):
        return nil
      try:
        toJS(ctx, c.toHex())
      except CatchableError as e:
        throwError(ctx, "toHex: " & e.msg, exception)
        nil

    module.registerFn toRgb:
      ## colors.toRgb(color) -> "rgb(r, g, b)"
      if not checkArity(argumentCount, 1, 1, "toRgb", ctx, exception):
        return nil
      var c: Color
      if not colorArg(ctx, args, 0, "toRgb", exception, c):
        return nil
      try:
        toJS(ctx, c.toRgbString())
      except CatchableError as e:
        throwError(ctx, "toRgb: " & e.msg, exception)
        nil

    module.registerFn toHsl:
      ## colors.toHsl(color) -> "hsl(h, s%, l%)"
      if not checkArity(argumentCount, 1, 1, "toHsl", ctx, exception):
        return nil
      var c: Color
      if not colorArg(ctx, args, 0, "toHsl", exception, c):
        return nil
      try:
        toJS(ctx, c.toHslString())
      except CatchableError as e:
        throwError(ctx, "toHsl: " & e.msg, exception)
        nil

    module.registerFn toName:
      ## colors.toName(color) -> nearest named color
      if not checkArity(argumentCount, 1, 1, "toName", ctx, exception):
        return nil
      var c: Color
      if not colorArg(ctx, args, 0, "toName", exception, c):
        return nil
      try:
        toJS(ctx, c.toName())
      except CatchableError as e:
        throwError(ctx, "toName: " & e.msg, exception)
        nil

    module.registerFn lighten:
      ## colors.lighten(color, amount) -> {r, g, b, a}
      if not checkArity(argumentCount, 2, 2, "lighten", ctx, exception):
        return nil
      var c: Color
      var amount: float
      if not colorArg(ctx, args, 0, "lighten", exception, c):
        return nil
      if not amountArg(ctx, args, 1, "lighten", exception, amount):
        return nil
      try:
        returnJson(ctx, colorToJson(c.lighten(amount)), "lighten",
          exception)
      except CatchableError as e:
        throwError(ctx, "lighten: " & e.msg, exception)
        nil

    module.registerFn darken:
      ## colors.darken(color, amount) -> {r, g, b, a}
      if not checkArity(argumentCount, 2, 2, "darken", ctx, exception):
        return nil
      var c: Color
      var amount: float
      if not colorArg(ctx, args, 0, "darken", exception, c):
        return nil
      if not amountArg(ctx, args, 1, "darken", exception, amount):
        return nil
      try:
        returnJson(ctx, colorToJson(c.darken(amount)), "darken", exception)
      except CatchableError as e:
        throwError(ctx, "darken: " & e.msg, exception)
        nil

    module.registerFn saturate:
      ## colors.saturate(color, amount) -> {r, g, b, a}
      if not checkArity(argumentCount, 2, 2, "saturate", ctx, exception):
        return nil
      var c: Color
      var amount: float
      if not colorArg(ctx, args, 0, "saturate", exception, c):
        return nil
      if not amountArg(ctx, args, 1, "saturate", exception, amount):
        return nil
      try:
        returnJson(ctx, colorToJson(c.saturate(amount)), "saturate",
          exception)
      except CatchableError as e:
        throwError(ctx, "saturate: " & e.msg, exception)
        nil

    module.registerFn spin:
      ## colors.spin(color, degrees) -> {r, g, b, a}
      if not checkArity(argumentCount, 2, 2, "spin", ctx, exception):
        return nil
      var c: Color
      var amount: float
      if not colorArg(ctx, args, 0, "spin", exception, c):
        return nil
      if not amountArg(ctx, args, 1, "spin", exception, amount):
        return nil
      try:
        returnJson(ctx, colorToJson(c.spin(amount)), "spin", exception)
      except CatchableError as e:
        throwError(ctx, "spin: " & e.msg, exception)
        nil

    module.registerFn complement:
      ## colors.complement(color) -> {r, g, b, a}
      if not checkArity(argumentCount, 1, 1, "complement", ctx, exception):
        return nil
      var c: Color
      if not colorArg(ctx, args, 0, "complement", exception, c):
        return nil
      try:
        returnJson(ctx, colorToJson(c.complement()), "complement",
          exception)
      except CatchableError as e:
        throwError(ctx, "complement: " & e.msg, exception)
        nil

    module.registerFn greyscale:
      ## colors.greyscale(color) -> {r, g, b, a}
      if not checkArity(argumentCount, 1, 1, "greyscale", ctx, exception):
        return nil
      var c: Color
      if not colorArg(ctx, args, 0, "greyscale", exception, c):
        return nil
      try:
        returnJson(ctx, colorToJson(c.greyscale()), "greyscale", exception)
      except CatchableError as e:
        throwError(ctx, "greyscale: " & e.msg, exception)
        nil

    module.registerFn mix:
      ## colors.mix(a, b[, weight]) -> {r, g, b, a} (weight 0..100, default 50)
      if not checkArity(argumentCount, 2, 3, "mix", ctx, exception):
        return nil
      var a, b: Color
      if not colorArg(ctx, args, 0, "mix", exception, a):
        return nil
      if not colorArg(ctx, args, 1, "mix", exception, b):
        return nil
      var weight = 50.0
      if int(argumentCount) == 3 and
          not amountArg(ctx, args, 2, "mix", exception, weight):
        return nil
      try:
        returnJson(ctx, colorToJson(mix(a, b, weight)), "mix", exception)
      except CatchableError as e:
        throwError(ctx, "mix: " & e.msg, exception)
        nil

    module.registerFn triad:
      ## colors.triad(color) -> [{r, g, b, a} x3]
      if not checkArity(argumentCount, 1, 1, "triad", ctx, exception):
        return nil
      var c: Color
      if not colorArg(ctx, args, 0, "triad", exception, c):
        return nil
      try:
        var arr = newJArray()
        for m in triad(c):
          arr.add(colorToJson(m))
        returnJson(ctx, arr, "triad", exception)
      except CatchableError as e:
        throwError(ctx, "triad: " & e.msg, exception)
        nil

    module.registerFn contrastRatio:
      ## colors.contrastRatio(a, b) -> 1..21
      if not checkArity(argumentCount, 2, 2, "contrastRatio", ctx,
          exception):
        return nil
      var a, b: Color
      if not colorArg(ctx, args, 0, "contrastRatio", exception, a):
        return nil
      if not colorArg(ctx, args, 1, "contrastRatio", exception, b):
        return nil
      try:
        toJS(ctx, contrastRatio(a, b))
      except CatchableError as e:
        throwError(ctx, "contrastRatio: " & e.msg, exception)
        nil

    module.registerFn isReadable:
      ## colors.isReadable(a, b) -> bool (WCAG AA, small text)
      if not checkArity(argumentCount, 2, 2, "isReadable", ctx, exception):
        return nil
      var a, b: Color
      if not colorArg(ctx, args, 0, "isReadable", exception, a):
        return nil
      if not colorArg(ctx, args, 1, "isReadable", exception, b):
        return nil
      try:
        toJS(ctx, isReadable(a, b))
      except CatchableError as e:
        throwError(ctx, "isReadable: " & e.msg, exception)
        nil

    module.registerFn isLight:
      ## colors.isLight(color) -> bool
      if not checkArity(argumentCount, 1, 1, "isLight", ctx, exception):
        return nil
      var c: Color
      if not colorArg(ctx, args, 0, "isLight", exception, c):
        return nil
      try:
        toJS(ctx, isLight(c))
      except CatchableError as e:
        throwError(ctx, "isLight: " & e.msg, exception)
        nil
