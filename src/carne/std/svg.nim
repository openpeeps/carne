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

import std/[json, tables]

import javascriptcore

import pkg/openparser/svg/parser
import pkg/openparser/svg/ast

import ../bridge

proc svgToJson(n: SvgNode): JsonNode =
  case n.kind
  of svgElement:
    var attrs = newJObject()
    for k, v in n.attrsRaw:
      attrs[k] = %v
    var children = newJArray()
    for c in n.children:
      children.add(svgToJson(c))
    %*{"kind": "element", "tag": tagName(n), "attrs": attrs,
      "children": children}
  of svgTextNode:
    %*{"kind": "text", "text": n.text}
  of svgCommentNode:
    %*{"kind": "comment", "text": n.comment}
  of svgCdataNode:
    %*{"kind": "cdata", "text": n.cdata}

## Builds the std/svg namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse:
      ## svg.parse(text) -> {tag, attrs, children}
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      try:
        let doc = parseSvg(text)
        if doc.root == nil:
          throwError(ctx, "parse: no root element", exception)
          return nil
        returnJson(ctx, svgToJson(doc.root), "parse", exception)
      except CatchableError as e:
        # Parser errors start with a newline + code snippet.
        throwError(ctx, "parse:" & e.msg, exception)
        nil
