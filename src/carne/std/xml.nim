# Carne std/xml: XML parsing and serialization via openparser.
#
#   const xml = require("std/xml");
#   xml.parse(text)   -> {tag, attrs, children} (text nodes are strings)
#   xml.stringify(node) -> string
#
# Elements + text/cdata only: comments, prologs and doctypes are dropped
# on parse. Roundtrip target: parse(stringify(parse(x))) deep-equals
# parse(x) for documents without those dropped nodes.

import std/tables

import javascriptcore

import pkg/openparser/xml

import ../bridge

proc xmlNodeToJS(ctx: JSContextRef; n: XmlNode): JSValueRef =
  ## XmlNode -> live JS value, no JsonNode middle layer. Non-content
  ## children (comments, prologs) are dropped, as before.
  case n.kind
  of xnElement:
    let attrs = newObject(ctx)
    var ex: JSValueRef = nil
    for k, v in n.attrs.pairs:
      setProp(ctx, attrs, k, toJS(ctx, v), addr ex)
      if ex != nil:
        return nil
    var vals: seq[JSValueRef] = @[]
    for c in n.children:
      case c.kind
      of xnElement, xnText, xnCdata:
        let j = xmlNodeToJS(ctx, c)
        if j == nil:
          return nil
        vals.add(j)
      else:
        discard
    var ex2: JSValueRef = nil
    let children =
      if vals.len > 0:
        JSObjectMakeArray(ctx, csize_t(vals.len), addr vals[0], addr ex2)
      else:
        JSObjectMakeArray(ctx, 0, nil, addr ex2)
    if ex2 != nil:
      return nil
    let obj = newObject(ctx)
    setProp(ctx, obj, "tag", toJS(ctx, n.tag), addr ex)
    setProp(ctx, obj, "attrs", attrs, addr ex)
    setProp(ctx, obj, "children", children, addr ex)
    if ex != nil:
      return nil
    result = obj
  of xnText:
    result = toJS(ctx, n.text)
  of xnCdata:
    result = toJS(ctx, n.cdata)
  else:
    result = JSValueMakeNull(ctx)

proc xmlErr(msg: string): ref CatchableError =
  newException(CatchableError, msg)

proc jsProp(ctx: JSContextRef; obj: JSValueRef; key: string): JSValueRef =
  ## Raw required property. Raises like the old validators.
  let k = newJSString(key)
  defer: JSStringRelease(k)
  var ex: JSValueRef = nil
  let prop = JSObjectGetProperty(ctx, obj, k, addr ex)
  if ex != nil or prop == nil:
    raise xmlErr("node object needs \"" & key & "\"")
  let t = JSValueGetType(ctx, prop)
  if t == kJSTypeUndefined:
    raise xmlErr("node object needs \"" & key & "\"")
  prop

proc jsToXmlNode(ctx: JSContextRef; v: JSValueRef; depth: int): XmlNode =
  ## {tag, attrs, children} (or a text string) -> XmlNode in one walk.
  if v == nil:
    raise xmlErr("node must be an object with tag/attrs/children")
  if depth > maxDumpDepth:
    raise xmlErr("node is too deeply nested or circular")
  if jsSkipped(ctx, v):
    raise xmlErr("node must be an object with tag/attrs/children")
  if JSValueGetType(ctx, v) == kJSTypeString:
    var ex: JSValueRef = nil
    let s = JSValueToStringCopy(ctx, v, addr ex)
    if s == nil:
      raise xmlErr("node must be an object with tag/attrs/children")
    defer: JSStringRelease(s)
    return XmlNode(kind: xnText, text: $s)
  if JSValueGetType(ctx, v) != kJSTypeObject or
      JSValueIsArray(ctx, v):
    raise xmlErr("node must be an object with tag/attrs/children")
  let tagProp = jsProp(ctx, v, "tag")
  if JSValueGetType(ctx, tagProp) != kJSTypeString:
    raise xmlErr("node object needs a string \"tag\"")
  var tagEx: JSValueRef = nil
  let tagStr = JSValueToStringCopy(ctx, tagProp, addr tagEx)
  if tagStr == nil:
    raise xmlErr("node object needs a string \"tag\"")
  defer: JSStringRelease(tagStr)
  let attrsProp = jsProp(ctx, v, "attrs")
  if JSValueGetType(ctx, attrsProp) != kJSTypeObject or
      JSValueIsArray(ctx, attrsProp):
    raise xmlErr("node object needs an object \"attrs\"")
  let childrenProp = jsProp(ctx, v, "children")
  if JSValueGetType(ctx, childrenProp) != kJSTypeObject or
      not JSValueIsArray(ctx, childrenProp):
    raise xmlErr("node object needs an array \"children\"")
  var attrs = initOrderedTable[string, string]()
  let names = JSObjectCopyPropertyNames(ctx, attrsProp)
  if names == nil:
    raise xmlErr("node object needs an object \"attrs\"")
  defer: JSPropertyNameArrayRelease(names)
  let count = int(JSPropertyNameArrayGetCount(names))
  for idx in 0 ..< count:
    let jsName = JSPropertyNameArrayGetNameAtIndex(names, csize_t(idx))
    let key = $jsName
    var pEx: JSValueRef = nil
    let aval = JSObjectGetProperty(ctx, attrsProp, jsName, addr pEx)
    if pEx != nil or aval == nil:
      raise xmlErr("attribute \"" & key & "\" must be a string")
    if JSValueGetType(ctx, aval) != kJSTypeString:
      raise xmlErr("attribute \"" & key & "\" must be a string")
    var aEx: JSValueRef = nil
    let aStr = JSValueToStringCopy(ctx, aval, addr aEx)
    if aStr == nil:
      raise xmlErr("attribute \"" & key & "\" must be a string")
    defer: JSStringRelease(aStr)
    attrs[key] = $aStr
  var lenEx: JSValueRef = nil
  let lenKey = newJSString("length")
  defer: JSStringRelease(lenKey)
  let lenV = JSObjectGetProperty(ctx, childrenProp, lenKey, addr lenEx)
  if lenEx != nil or lenV == nil:
    raise xmlErr("node object needs an array \"children\"")
  var lenEx2: JSValueRef = nil
  let n = int(JSValueToNumber(ctx, lenV, addr lenEx2))
  if lenEx2 != nil or n < 0:
    raise xmlErr("node object needs an array \"children\"")
  var children: seq[XmlNode] = @[]
  for idx in 0 ..< n:
    var eEx: JSValueRef = nil
    let item = JSObjectGetPropertyAtIndex(ctx, childrenProp, cuint(idx),
      addr eEx)
    if eEx != nil or item == nil:
      raise xmlErr("node must be an object with tag/attrs/children")
    children.add(jsToXmlNode(ctx, item, depth + 1))
  XmlNode(kind: xnElement, tag: $tagStr, attrs: attrs,
    children: children)

## Builds the std/xml namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## xml.parse(text) -> {tag, attrs, children}
      try:
        let node = fromXml(text)
        if node == nil or node.kind != xnElement:
          throwError(ctx, "parse: no root element", exception)
          return nil
        let j = xmlNodeToJS(ctx, node)
        if j == nil:
          throwError(ctx, "parse: could not convert result to JS",
            exception)
          return nil
        j
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify(value: JSValueRef):
      ## xml.stringify(node) -> string
      try:
        let node = jsToXmlNode(ctx, value, 0)
        if node.kind != xnElement:
          throwError(ctx, "stringify: root must be an object with tag/attrs/children",
            exception)
          return nil
        toJS(ctx, toXml(node))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
