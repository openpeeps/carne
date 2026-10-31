# Carne std/css: CSS parsing and declaration validation via openparser.
#
#   const css = require("std/css");
#   css.parse("a { color: red; }")
#     -> {rules: [{kind: "RuleSet", selectors: [...], declarations: [...]}]}
#   css.validate("a { color: red; bogus: 1; }")
#     -> [{property: "bogus", valid: false, errors: [...]}] ([] when clean)
#
# Declaration nodes carry the raw value text plus the important flag;
# selector/value detail is preserved in parts/components.

import std/strutils

import javascriptcore

import pkg/openparser/css

import ../bridge

proc cssValueToJS(ctx: JSContextRef; v: CssValue; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  ## CssValue -> live JS value, no JsonNode middle layer.
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "kind", toJS(ctx, ($v.kind)[3 .. ^1]),
      fname, exception):
    return nil
  case v.kind
  of cvkFunction:
    if not setPropChecked(ctx, obj, "name", toJS(ctx, v.funcName),
        fname, exception):
      return nil
    var vals: seq[JSValueRef] = @[]
    for a in v.args:
      let j = cssValueToJS(ctx, a, fname, exception)
      if j == nil:
        return nil
      vals.add(j)
    let args = makeJSArray(ctx, vals)
    if args == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "args", args, fname, exception):
      return nil
  of cvkNumber:
    if not setPropChecked(ctx, obj, "value", toJS(ctx, v.numValue),
        fname, exception):
      return nil
  of cvkDimension:
    if not setPropChecked(ctx, obj, "value", toJS(ctx, v.dimValue),
        fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "unit", toJS(ctx, v.dimUnit),
        fname, exception):
      return nil
  of cvkPercentage:
    if not setPropChecked(ctx, obj, "value", toJS(ctx, v.pctValue),
        fname, exception):
      return nil
  of cvkString:
    if not setPropChecked(ctx, obj, "value", toJS(ctx, v.strValue),
        fname, exception):
      return nil
  of cvkUrl:
    if not setPropChecked(ctx, obj, "value", toJS(ctx, v.urlValue),
        fname, exception):
      return nil
  of cvkIdent:
    if not setPropChecked(ctx, obj, "value", toJS(ctx, v.identValue),
        fname, exception):
      return nil
  of cvkHash:
    if not setPropChecked(ctx, obj, "value", toJS(ctx, v.hashValue),
        fname, exception):
      return nil
  of cvkImportant:
    if not setPropChecked(ctx, obj, "important", toJS(ctx, true),
        fname, exception):
      return nil
  of cvkBlock:
    var vals: seq[JSValueRef] = @[]
    for b in v.blockValues:
      let j = cssValueToJS(ctx, b, fname, exception)
      if j == nil:
        return nil
      vals.add(j)
    let arr = makeJSArray(ctx, vals)
    if arr == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "values", arr, fname, exception):
      return nil
  of cvkPreserved:
    if not setPropChecked(ctx, obj, "value", toJS(ctx, v.preservedValue),
        fname, exception):
      return nil
  of cvkComment:
    if not setPropChecked(ctx, obj, "text", toJS(ctx, v.commentText),
        fname, exception):
      return nil
  result = obj

proc cssValsToJS(ctx: JSContextRef; vals: seq[CssValue]; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  var outs: seq[JSValueRef] = @[]
  for v in vals:
    let j = cssValueToJS(ctx, v, fname, exception)
    if j == nil:
      return nil
    outs.add(j)
  let arr = makeJSArray(ctx, outs)
  if arr == nil:
    throwError(ctx, fname & ": could not convert result to JS",
      exception)
    return nil
  arr

proc cssNodeToJS(ctx: JSContextRef; n: CssNode; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  ## CssNode -> live JS value, no JsonNode middle layer.
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "kind", toJS(ctx, ($n.kind)[3 .. ^1]),
      fname, exception):
    return nil
  case n.kind
  of cssStyleSheet:
    var vals: seq[JSValueRef] = @[]
    for r in n.rules:
      let j = cssNodeToJS(ctx, r, fname, exception)
      if j == nil:
        return nil
      vals.add(j)
    let rules = makeJSArray(ctx, vals)
    if rules == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "rules", rules, fname, exception):
      return nil
  of cssRuleSet:
    var sels: seq[JSValueRef] = @[]
    for s in n.selectors:
      let j = cssNodeToJS(ctx, s, fname, exception)
      if j == nil:
        return nil
      sels.add(j)
    let selArr = makeJSArray(ctx, sels)
    if selArr == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "selectors", selArr, fname,
        exception):
      return nil
    var decls: seq[JSValueRef] = @[]
    for d in n.declarations:
      let j = cssNodeToJS(ctx, d, fname, exception)
      if j == nil:
        return nil
      decls.add(j)
    let declArr = makeJSArray(ctx, decls)
    if declArr == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "declarations", declArr, fname,
        exception):
      return nil
  of cssSelector:
    if not setPropChecked(ctx, obj, "selectorKind",
        toJS(ctx, ($n.selectorKind)[8 .. ^1]), fname, exception):
      return nil
    var parts: seq[JSValueRef] = @[]
    for p in n.parts:
      parts.add(toJS(ctx, p))
    let partArr = makeJSArray(ctx, parts)
    if partArr == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "parts", partArr, fname, exception):
      return nil
  of cssDeclaration:
    if not setPropChecked(ctx, obj, "property", toJS(ctx, n.property),
        fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "value", toJS(ctx, n.rawValue),
        fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "important", toJS(ctx, n.important),
        fname, exception):
      return nil
  of cssComment:
    if not setPropChecked(ctx, obj, "text", toJS(ctx, n.text), fname,
        exception):
      return nil
  of cssAtRule:
    if not setPropChecked(ctx, obj, "name", toJS(ctx, n.atName), fname,
        exception):
      return nil
    if not setPropChecked(ctx, obj, "prelude", toJS(ctx, n.prelude),
        fname, exception):
      return nil
    var rvals: seq[JSValueRef] = @[]
    for r in n.atRules:
      let j = cssNodeToJS(ctx, r, fname, exception)
      if j == nil:
        return nil
      rvals.add(j)
    let rules = makeJSArray(ctx, rvals)
    if rules == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "rules", rules, fname, exception):
      return nil
    let bvals = cssValsToJS(ctx, n.blockValues, fname, exception)
    if bvals == nil:
      return nil
    if not setPropChecked(ctx, obj, "values", bvals, fname, exception):
      return nil
  of cssValue:
    if not setPropChecked(ctx, obj, "raw", toJS(ctx, n.raw), fname,
        exception):
      return nil
    let comps = cssValsToJS(ctx, n.components, fname, exception)
    if comps == nil:
      return nil
    if not setPropChecked(ctx, obj, "values", comps, fname, exception):
      return nil
  result = obj

const VendorPrefixes = ["-webkit-", "-moz-", "-ms-", "-o-"]

proc knownProperty(data: CssData; prop: string): bool =
  ## Custom properties are always valid; otherwise the name (modulo a
  ## single vendor prefix) must exist in the spec tables.
  if prop.startsWith("--"):
    return true
  if getPropertySyntax(data, prop) != nil:
    return true
  for prefix in VendorPrefixes:
    if prop.startsWith(prefix) and
        getPropertySyntax(data, prop[prefix.len .. ^1]) != nil:
      return true
  false

proc checkDecl(ctx: JSContextRef; data: CssData; decl: CssNode;
    fname: string; exception: ptr JSValueRef;
    arr: var seq[JSValueRef]): bool =
  ## False + JS throw when a problem object fails to build.
  if decl.kind != cssDeclaration:
    return true
  if not knownProperty(data, decl.property):
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "property", toJS(ctx, decl.property),
        fname, exception):
      return false
    if not setPropChecked(ctx, obj, "value", toJS(ctx, decl.rawValue),
        fname, exception):
      return false
    if not setPropChecked(ctx, obj, "valid", toJS(ctx, false), fname,
        exception):
      return false
    let errObj = newObject(ctx)
    if not setPropChecked(ctx, errObj, "message",
        toJS(ctx, "Unknown property"), fname, exception):
      return false
    if not setPropChecked(ctx, errObj, "property",
        toJS(ctx, decl.property), fname, exception):
      return false
    if not setPropChecked(ctx, errObj, "value", toJS(ctx, decl.rawValue),
        fname, exception):
      return false
    let errs = makeJSArray(ctx, [errObj])
    if errs == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return false
    if not setPropChecked(ctx, obj, "errors", errs, fname, exception):
      return false
    arr.add(obj)
    return true
  let res = validateDeclaration(data, decl)
  if not res.valid:
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "property", toJS(ctx, decl.property),
        fname, exception):
      return false
    if not setPropChecked(ctx, obj, "value", toJS(ctx, decl.rawValue),
        fname, exception):
      return false
    if not setPropChecked(ctx, obj, "valid", toJS(ctx, false), fname,
        exception):
      return false
    var evals: seq[JSValueRef] = @[]
    for e in res.errors:
      let errObj = newObject(ctx)
      if not setPropChecked(ctx, errObj, "message", toJS(ctx, e.message),
          fname, exception):
        return false
      if not setPropChecked(ctx, errObj, "property", toJS(ctx, e.property),
          fname, exception):
        return false
      if not setPropChecked(ctx, errObj, "value", toJS(ctx, e.value),
          fname, exception):
        return false
      evals.add(errObj)
    let errs = makeJSArray(ctx, evals)
    if errs == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return false
    if not setPropChecked(ctx, obj, "errors", errs, fname, exception):
      return false
    arr.add(obj)
  true

proc checkNode(ctx: JSContextRef; data: CssData; node: CssNode;
    fname: string; exception: ptr JSValueRef;
    arr: var seq[JSValueRef]): bool =
  case node.kind
  of cssRuleSet:
    for decl in node.declarations:
      if not checkDecl(ctx, data, decl, fname, exception, arr):
        return false
    true
  of cssAtRule:
    for child in node.atRules:
      if child.kind == cssDeclaration:
        if not checkDecl(ctx, data, child, fname, exception, arr):
          return false
      else:
        if not checkNode(ctx, data, child, fname, exception, arr):
          return false
    true
  else:
    true

var cssDataReady = false
var cssData: CssData

proc getCssData(): CssData =
  ## loadCssData parses the embedded spec tables; cache across calls.
  if not cssDataReady:
    cssData = loadCssData()
    cssDataReady = true
  cssData

## Builds the std/css namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## css.parse(text) -> {rules: [...]}
      try:
        let sheet = parseCss(text)
        var vals: seq[JSValueRef] = @[]
        for r in sheet.nodes:
          let j = cssNodeToJS(ctx, r, "parse", exception)
          if j == nil:
            return nil
          vals.add(j)
        let rules = makeJSArray(ctx, vals)
        if rules == nil:
          throwError(ctx, "parse: could not convert result to JS",
            exception)
          return nil
        let obj = newObject(ctx)
        if not setPropChecked(ctx, obj, "rules", rules, "parse",
            exception):
          return nil
        obj
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn validate(text: string):
      ## css.validate(text) -> problems per declaration ([] when clean)
      try:
        let data = getCssData()
        var vals: seq[JSValueRef] = @[]
        for node in parseCss(text).nodes:
          if not checkNode(ctx, data, node, "validate", exception, vals):
            return nil
        let arr = makeJSArray(ctx, vals)
        if arr == nil:
          throwError(ctx, "validate: could not convert result to JS",
            exception)
          return nil
        arr
      except CatchableError as e:
        throwError(ctx, "validate: " & e.msg, exception)
        nil
