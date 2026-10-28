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

import std/[json, strutils]

import javascriptcore

import pkg/openparser/css

import ../bridge

proc cssValueToJson(v: CssValue): JsonNode =
  result = newJObject()
  result["kind"] = %($v.kind)[3 .. ^1]
  case v.kind
  of cvkFunction:
    result["name"] = %v.funcName
    var args = newJArray()
    for a in v.args:
      args.add(cssValueToJson(a))
    result["args"] = args
  of cvkNumber:
    result["value"] = %v.numValue
  of cvkDimension:
    result["value"] = %v.dimValue
    result["unit"] = %v.dimUnit
  of cvkPercentage:
    result["value"] = %v.pctValue
  of cvkString:
    result["value"] = %v.strValue
  of cvkUrl:
    result["value"] = %v.urlValue
  of cvkIdent:
    result["value"] = %v.identValue
  of cvkHash:
    result["value"] = %v.hashValue
  of cvkImportant:
    result["important"] = %true
  of cvkBlock:
    var vals = newJArray()
    for b in v.blockValues:
      vals.add(cssValueToJson(b))
    result["values"] = vals
  of cvkPreserved:
    result["value"] = %v.preservedValue
  of cvkComment:
    result["text"] = %v.commentText

proc cssNodeToJson(n: CssNode): JsonNode =
  result = newJObject()
  result["kind"] = %($n.kind)[3 .. ^1]
  case n.kind
  of cssStyleSheet:
    var rules = newJArray()
    for r in n.rules:
      rules.add(cssNodeToJson(r))
    result["rules"] = rules
  of cssRuleSet:
    var sels = newJArray()
    for s in n.selectors:
      sels.add(cssNodeToJson(s))
    result["selectors"] = sels
    var decls = newJArray()
    for d in n.declarations:
      decls.add(cssNodeToJson(d))
    result["declarations"] = decls
  of cssSelector:
    result["selectorKind"] = %($n.selectorKind)[8 .. ^1]
    var parts = newJArray()
    for p in n.parts:
      parts.add(%p)
    result["parts"] = parts
  of cssDeclaration:
    result["property"] = %n.property
    result["value"] = %n.rawValue
    result["important"] = %n.important
  of cssComment:
    result["text"] = %n.text
  of cssAtRule:
    result["name"] = %n.atName
    result["prelude"] = %n.prelude
    var rules = newJArray()
    for r in n.atRules:
      rules.add(cssNodeToJson(r))
    result["rules"] = rules
    var vals = newJArray()
    for v in n.blockValues:
      vals.add(cssValueToJson(v))
    result["values"] = vals
  of cssValue:
    result["raw"] = %n.raw
    var comps = newJArray()
    for c in n.components:
      comps.add(cssValueToJson(c))
    result["values"] = comps

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

proc checkDecl(data: CssData; decl: CssNode; arr: var JsonNode) =
  if decl.kind != cssDeclaration:
    return
  if not knownProperty(data, decl.property):
    arr.add(%*{"property": decl.property, "value": decl.rawValue,
      "valid": false,
      "errors": [{"message": "Unknown property",
        "property": decl.property, "value": decl.rawValue}]})
    return
  let res = validateDeclaration(data, decl)
  if not res.valid:
    var obj = newJObject()
    obj["property"] = %decl.property
    obj["value"] = %decl.rawValue
    obj["valid"] = %false
    var errs = newJArray()
    for e in res.errors:
      errs.add(%*{"message": e.message, "property": e.property,
        "value": e.value})
    obj["errors"] = errs
    arr.add(obj)

proc checkNode(data: CssData; node: CssNode; arr: var JsonNode) =
  case node.kind
  of cssRuleSet:
    for decl in node.declarations:
      checkDecl(data, decl, arr)
  of cssAtRule:
    for child in node.atRules:
      if child.kind == cssDeclaration:
        checkDecl(data, child, arr)
      else:
        checkNode(data, child, arr)
  else:
    discard

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

    module.registerFn parse:
      ## css.parse(text) -> {rules: [...]}
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      try:
        let sheet = parseCss(text)
        var rules = newJArray()
        for r in sheet.nodes:
          rules.add(cssNodeToJson(r))
        returnJson(ctx, %*{"rules": rules}, "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn validate:
      ## css.validate(text) -> problems per declaration ([] when clean)
      if not checkArity(argumentCount, 1, 1, "validate", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "validate", exception, text):
        return nil
      try:
        let data = getCssData()
        var arr = newJArray()
        for node in parseCss(text).nodes:
          checkNode(data, node, arr)
        returnJson(ctx, arr, "validate", exception)
      except CatchableError as e:
        throwError(ctx, "validate: " & e.msg, exception)
        nil
