# Carne std/svg: SVG parsing via openparser.
#
#   const svg = require("std/svg");
#   svg.parse('<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>')
#     -> {tag: "svg", attrs: {...}, children: [...]}
#
# Elements map to {tag, attrs, children} (same shape as std/xml);
# text, comments and CDATA become {kind, text} leaves. Serialization
# is out of scope in v1 (the typed AST does not roundtrip through
# plain JSON); pair with std/xml when you need to write SVG.

import std/[tables]

import javascriptcore

import pkg/openparser/svg/parser
import pkg/openparser/svg/ast

import ../bridge

proc svgToJS(ctx: JSContextRef; n: SvgNode; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  ## SvgNode -> live JS value, no JsonNode middle layer.
  case n.kind
  of svgElement:
    let attrs = newObject(ctx)
    for k, v in n.attrsRaw:
      if not setPropChecked(ctx, attrs, k, toJS(ctx, v), fname,
          exception):
        return nil
    var vals: seq[JSValueRef] = @[]
    for c in n.children:
      let j = svgToJS(ctx, c, fname, exception)
      if j == nil:
        return nil
      vals.add(j)
    var ex: JSValueRef = nil
    let children =
      if vals.len > 0:
        JSObjectMakeArray(ctx, csize_t(vals.len), addr vals[0], addr ex)
      else:
        JSObjectMakeArray(ctx, 0, nil, addr ex)
    if ex != nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "kind", toJS(ctx, "element"), fname,
        exception):
      return nil
    if not setPropChecked(ctx, obj, "tag", toJS(ctx, tagName(n)), fname,
        exception):
      return nil
    if not setPropChecked(ctx, obj, "attrs", attrs, fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "children", children, fname,
        exception):
      return nil
    result = obj
  of svgTextNode:
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "kind", toJS(ctx, "text"), fname,
        exception):
      return nil
    if not setPropChecked(ctx, obj, "text", toJS(ctx, n.text), fname,
        exception):
      return nil
    result = obj
  of svgCommentNode:
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "kind", toJS(ctx, "comment"), fname,
        exception):
      return nil
    if not setPropChecked(ctx, obj, "text", toJS(ctx, n.comment), fname,
        exception):
      return nil
    result = obj
  of svgCdataNode:
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "kind", toJS(ctx, "cdata"), fname,
        exception):
      return nil
    if not setPropChecked(ctx, obj, "text", toJS(ctx, n.cdata), fname,
        exception):
      return nil
    result = obj

## Builds the std/svg namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## svg.parse(text) -> {tag, attrs, children}
      try:
        let doc = parseSvg(text)
        if doc.root == nil:
          throwError(ctx, "parse: no root element", exception)
          return nil
        let j = svgToJS(ctx, doc.root, "parse", exception)
        if j == nil:
          throwError(ctx, "parse: could not convert result to JS",
            exception)
          return nil
        j
      except CatchableError as e:
        # Parser errors start with a newline + code snippet.
        throwError(ctx, "parse:" & e.msg, exception)
        nil
