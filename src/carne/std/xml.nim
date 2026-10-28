# Carne std/xml: XML parsing and serialization via openparser.
#
#   const xml = require("std/xml");
#   xml.parse(text)   -> {tag, attrs, children} (text nodes are strings)
#   xml.stringify(node) -> string
#
# Elements + text/cdata only: comments, prologs and doctypes are dropped
# on parse. Roundtrip target: parse(stringify(parse(x))) deep-equals
# parse(x) for documents without those dropped nodes.

import std/[json, tables]

import javascriptcore

import pkg/openparser/xml

import ../bridge

proc xmlToJson(n: XmlNode): JsonNode =
  case n.kind
  of xnElement:
    let attrs = newJObject()
    for k, v in n.attrs:
      attrs[k] = %v
    let children = newJArray()
    for c in n.children:
      case c.kind
      of xnElement, xnText, xnCdata:
        children.add(xmlToJson(c))
      else:
        discard
    %*{"tag": n.tag, "attrs": attrs, "children": children}
  of xnText:
    %n.text
  of xnCdata:
    %n.cdata
  else:
    newJNull()

proc jsonToXmlErr(msg: string): ref CatchableError =
  newException(CatchableError, msg)

proc jsonToXml(j: JsonNode): XmlNode =
  if j.kind == JString:
    return XmlNode(kind: xnText, text: j.getStr())
  if j.kind != JObject:
    raise jsonToXmlErr("node must be an object with tag/attrs/children")
  if not j.hasKey("tag") or j["tag"].kind != JString:
    raise jsonToXmlErr("node object needs a string \"tag\"")
  if not j.hasKey("attrs") or j["attrs"].kind != JObject:
    raise jsonToXmlErr("node object needs an object \"attrs\"")
  if not j.hasKey("children") or j["children"].kind != JArray:
    raise jsonToXmlErr("node object needs an array \"children\"")
  var attrs = initOrderedTable[string, string]()
  for k, v in j["attrs"].pairs:
    if v.kind != JString:
      raise jsonToXmlErr("attribute \"" & k & "\" must be a string")
    attrs[k] = v.getStr()
  var children: seq[XmlNode] = @[]
  for c in j["children"]:
    children.add(jsonToXml(c))
  XmlNode(kind: xnElement, tag: j["tag"].getStr(), attrs: attrs,
    children: children)

## Builds the std/xml namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse:
      ## xml.parse(text) -> {tag, attrs, children}
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      try:
        let node = fromXml(text)
        if node == nil or node.kind != xnElement:
          throwError(ctx, "parse: no root element", exception)
          return nil
        returnJson(ctx, xmlToJson(node), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify:
      ## xml.stringify(node) -> string
      if not checkArity(argumentCount, 1, 1, "stringify", ctx, exception):
        return nil
      var err = ""
      let node = jsToJson(ctx, args[0], err)
      if node == nil:
        throwError(ctx, "stringify: " & err, exception)
        return nil
      if node.kind != JObject:
        throwError(ctx, "stringify: root must be an object with tag/attrs/children",
          exception)
        return nil
      try:
        toJS(ctx, toXml(jsonToXml(node)))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
