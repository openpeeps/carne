# Carne std/colors: color parsing, formatting and math (pure JS).
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
# Accepts hex, rgb()/hsl()/hsv()/cmyk()/lab()/lch()/oklab()/oklch()
# strings and named colors.
#
# The implementation lives in js/colors.js (CommonJS). It is embedded
# at build time via slurp and evaluated on first require, so the
# binary has no runtime file dependency and no openparser dependency
# for colors.

import javascriptcore

import ../bridge

const colorsJsSource = slurp("js/colors.js")

proc install*(ctx: JSContextRef; rt: Runtime): JSObjectRef =
  ## Loads the bundled JS implementation as a CommonJS module and
  ## returns its `module.exports`. nil on failure (require reports
  ## "failed to initialize").
  let moduleObj = newObject(ctx)
  let exportsObj = newObject(ctx)
  var setupEx: JSValueRef = nil
  setProp(ctx, moduleObj, "exports", exportsObj, addr setupEx)
  if setupEx != nil:
    return nil
  let wrapped = "(function(module, exports) {\n" & colorsJsSource & "\n})"
  var ex: JSValueRef = nil
  let fn = evalScript(ctx, wrapped, sourceURL = "std/colors.js",
    exception = ex)
  if ex != nil or fn == nil or not JSValueIsObject(ctx, fn):
    return nil
  let fnObj = cast[JSObjectRef](fn)
  if not JSObjectIsFunction(ctx, fnObj):
    return nil
  var callEx: JSValueRef = nil
  var args: array[2, JSValueRef]
  args[0] = moduleObj
  args[1] = exportsObj
  discard JSObjectCallAsFunction(ctx, fnObj, nil, 2, addr args[0],
    addr callEx)
  if callEx != nil:
    return nil
  var getEx: JSValueRef = nil
  let key = newJSString("exports")
  defer: JSStringRelease(key)
  let finalExp = JSObjectGetProperty(ctx, moduleObj, key, addr getEx)
  if getEx != nil or finalExp == nil or
      not JSValueIsObject(ctx, finalExp):
    return nil
  cast[JSObjectRef](finalExp)
