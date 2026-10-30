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

proc numField(v: NimValue; field, name: string): float =
  ## Reads a numeric field as float. Raises on anything else.
  if not v.hasKey(field):
    raise newException(CatchableError, "color needs numeric \"" & field & "\"")
  let f = v.get(field, name)
  case f.kind
  of nvkInt:
    float(f.i)
  of nvkFloat:
    f.f
  else:
    raise newException(CatchableError, "color needs numeric \"" & field & "\"")

proc colorVal(v: NimValue; name, docBlock: string; ctx: JSContextRef;
    exception: ptr JSValueRef; color: var Color): bool =
  ## Reads a snapshot as a {r, g, b, a?} object. False + JS throw.
  template oerr(msg: string): untyped =
    throwError(ctx,
      (if docBlock.len > 0: docBlock & "\n" else: "") & msg, exception)
  if v.kind != nvkObject:
    oerr(name & ": color must be an {r, g, b, a?} object")
    return false
  try:
    var c = Color(a: 1.0)
    c.r = numField(v, "r", name) / 255.0
    c.g = numField(v, "g", name) / 255.0
    c.b = numField(v, "b", name) / 255.0
    if v.hasKey("a"):
      c.a = numField(v, "a", name)
    if c.r < 0.0 or c.r > 1.0 or c.g < 0.0 or c.g > 1.0 or
        c.b < 0.0 or c.b > 1.0 or c.a < 0.0 or c.a > 1.0:
      oerr(name & ": r/g/b must be 0..255 and a 0..1")
      return false
    color = c
    true
  except CatchableError as e:
    oerr(name & ": " & e.msg)
    false

## Builds the std/colors namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## colors.parse(text) -> {r, g, b, a}
      try:
        returnJson(ctx, colorToJson(parseColor(text)), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn random():
      ## colors.random() -> {r, g, b, a}
      try:
        returnJson(ctx, colorToJson(randomColor()), "random", exception)
      except CatchableError as e:
        throwError(ctx, "random: " & e.msg, exception)
        nil

    module.registerFn toHex(color: NimValue):
      ## colors.toHex(color) -> "#rrggbb"
      var c: Color
      if not colorVal(color, "toHex", docBlock, ctx, exception, c):
        return nil
      try:
        toJS(ctx, c.toHex())
      except CatchableError as e:
        throwError(ctx, "toHex: " & e.msg, exception)
        nil

    module.registerFn toRgb(color: NimValue):
      ## colors.toRgb(color) -> "rgb(r, g, b)"
      var c: Color
      if not colorVal(color, "toRgb", docBlock, ctx, exception, c):
        return nil
      try:
        toJS(ctx, c.toRgbString())
      except CatchableError as e:
        throwError(ctx, "toRgb: " & e.msg, exception)
        nil

    module.registerFn toHsl(color: NimValue):
      ## colors.toHsl(color) -> "hsl(h, s%, l%)"
      var c: Color
      if not colorVal(color, "toHsl", docBlock, ctx, exception, c):
        return nil
      try:
        toJS(ctx, c.toHslString())
      except CatchableError as e:
        throwError(ctx, "toHsl: " & e.msg, exception)
        nil

    module.registerFn toName(color: NimValue):
      ## colors.toName(color) -> nearest named color
      var c: Color
      if not colorVal(color, "toName", docBlock, ctx, exception, c):
        return nil
      try:
        toJS(ctx, c.toName())
      except CatchableError as e:
        throwError(ctx, "toName: " & e.msg, exception)
        nil

    module.registerFn lighten(color: NimValue, amount: float):
      ## colors.lighten(color, amount) -> {r, g, b, a}
      var c: Color
      if not colorVal(color, "lighten", docBlock, ctx, exception, c):
        return nil
      try:
        returnJson(ctx, colorToJson(c.lighten(amount)), "lighten",
          exception)
      except CatchableError as e:
        throwError(ctx, "lighten: " & e.msg, exception)
        nil

    module.registerFn darken(color: NimValue, amount: float):
      ## colors.darken(color, amount) -> {r, g, b, a}
      var c: Color
      if not colorVal(color, "darken", docBlock, ctx, exception, c):
        return nil
      try:
        returnJson(ctx, colorToJson(c.darken(amount)), "darken", exception)
      except CatchableError as e:
        throwError(ctx, "darken: " & e.msg, exception)
        nil

    module.registerFn saturate(color: NimValue, amount: float):
      ## colors.saturate(color, amount) -> {r, g, b, a}
      var c: Color
      if not colorVal(color, "saturate", docBlock, ctx, exception, c):
        return nil
      try:
        returnJson(ctx, colorToJson(c.saturate(amount)), "saturate",
          exception)
      except CatchableError as e:
        throwError(ctx, "saturate: " & e.msg, exception)
        nil

    module.registerFn spin(color: NimValue, amount: float):
      ## colors.spin(color, degrees) -> {r, g, b, a}
      var c: Color
      if not colorVal(color, "spin", docBlock, ctx, exception, c):
        return nil
      try:
        returnJson(ctx, colorToJson(c.spin(amount)), "spin", exception)
      except CatchableError as e:
        throwError(ctx, "spin: " & e.msg, exception)
        nil

    module.registerFn complement(color: NimValue):
      ## colors.complement(color) -> {r, g, b, a}
      var c: Color
      if not colorVal(color, "complement", docBlock, ctx, exception, c):
        return nil
      try:
        returnJson(ctx, colorToJson(c.complement()), "complement",
          exception)
      except CatchableError as e:
        throwError(ctx, "complement: " & e.msg, exception)
        nil

    module.registerFn greyscale(color: NimValue):
      ## colors.greyscale(color) -> {r, g, b, a}
      var c: Color
      if not colorVal(color, "greyscale", docBlock, ctx, exception, c):
        return nil
      try:
        returnJson(ctx, colorToJson(c.greyscale()), "greyscale", exception)
      except CatchableError as e:
        throwError(ctx, "greyscale: " & e.msg, exception)
        nil

    module.registerFn mix(aVal: NimValue, bVal: NimValue,
        weight: default(float, 50.0)):
      ## colors.mix(a, b[, weight]) -> {r, g, b, a} (weight 0..100, default 50)
      var a, b: Color
      if not colorVal(aVal, "mix", docBlock, ctx, exception, a):
        return nil
      if not colorVal(bVal, "mix", docBlock, ctx, exception, b):
        return nil
      try:
        returnJson(ctx, colorToJson(mix(a, b, weight)), "mix", exception)
      except CatchableError as e:
        throwError(ctx, "mix: " & e.msg, exception)
        nil

    module.registerFn triad(color: NimValue):
      ## colors.triad(color) -> [{r, g, b, a} x3]
      var c: Color
      if not colorVal(color, "triad", docBlock, ctx, exception, c):
        return nil
      try:
        var arr = newJArray()
        for m in triad(c):
          arr.add(colorToJson(m))
        returnJson(ctx, arr, "triad", exception)
      except CatchableError as e:
        throwError(ctx, "triad: " & e.msg, exception)
        nil

    module.registerFn contrastRatio(aVal: NimValue, bVal: NimValue):
      ## colors.contrastRatio(a, b) -> 1..21
      var a, b: Color
      if not colorVal(aVal, "contrastRatio", docBlock, ctx, exception, a):
        return nil
      if not colorVal(bVal, "contrastRatio", docBlock, ctx, exception, b):
        return nil
      try:
        toJS(ctx, contrastRatio(a, b))
      except CatchableError as e:
        throwError(ctx, "contrastRatio: " & e.msg, exception)
        nil

    module.registerFn isReadable(aVal: NimValue, bVal: NimValue):
      ## colors.isReadable(a, b) -> bool (WCAG AA, small text)
      var a, b: Color
      if not colorVal(aVal, "isReadable", docBlock, ctx, exception, a):
        return nil
      if not colorVal(bVal, "isReadable", docBlock, ctx, exception, b):
        return nil
      try:
        toJS(ctx, isReadable(a, b))
      except CatchableError as e:
        throwError(ctx, "isReadable: " & e.msg, exception)
        nil

    module.registerFn isLight(color: NimValue):
      ## colors.isLight(color) -> bool
      var c: Color
      if not colorVal(color, "isLight", docBlock, ctx, exception, c):
        return nil
      try:
        toJS(ctx, isLight(c))
      except CatchableError as e:
        throwError(ctx, "isLight: " & e.msg, exception)
        nil
