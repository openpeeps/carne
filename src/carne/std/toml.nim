# Carne std/toml: TOML parsing and serialization via openparser.
#
#   const toml = require("std/toml");
#   toml.parse(text)      -> object (document root must be a table)
#   toml.stringify(obj)   -> string
#
# TOML datetimes surface as strings (the literal as written) and
# stringify back as TOML strings: the datetime type does not roundtrip.

import std/[math, tables]

import javascriptcore

import pkg/openparser/toml

import ../bridge

proc tomlNodeToJS(ctx: JSContextRef; n: TomlNode): JSValueRef =
  ## TomlNode -> live JS value, no JsonNode middle layer.
  case n.kind
  of tvkString, tvkDateTime:
    # Datetimes surface as the literal as written (documented).
    result = toJS(ctx, if n.kind == tvkString: n.strVal else: n.dateRaw)
  of tvkInteger:
    result = toJS(ctx, n.intVal)
  of tvkFloat:
    result = toJS(ctx, n.floatVal)
  of tvkBoolean:
    result = toJS(ctx, n.boolVal)
  of tvkArray:
    var vals: seq[JSValueRef] = @[]
    for item in n.arrayVal:
      let j = tomlNodeToJS(ctx, item)
      if j == nil:
        return nil
      vals.add(j)
    var ex: JSValueRef = nil
    let arr =
      if vals.len > 0:
        JSObjectMakeArray(ctx, csize_t(vals.len), addr vals[0], addr ex)
      else:
        JSObjectMakeArray(ctx, 0, nil, addr ex)
    if ex != nil:
      result = nil
    else:
      result = arr
  of tvkTable:
    let obj = newObject(ctx)
    var ex: JSValueRef = nil
    for k, v in n.tableVal.pairs:
      let j = tomlNodeToJS(ctx, v)
      if j == nil:
        return nil
      setProp(ctx, obj, k, j, addr ex)
      if ex != nil:
        return nil
    result = obj

proc tomlErr(msg: string): ref CatchableError =
  newException(CatchableError, msg)

proc jsScalarToToml(ctx: JSContextRef; v: JSValueRef): TomlNode =
  ## Numbers/strings/bools only. Raises like the old jsonToToml.
  case JSValueGetType(ctx, v)
  of kJSTypeString:
    var ex: JSValueRef = nil
    let s = JSValueToStringCopy(ctx, v, addr ex)
    if s == nil:
      raise tomlErr("is not convertible to string")
    defer: JSStringRelease(s)
    TomlNode(kind: tvkString, strVal: $s)
  of kJSTypeBoolean:
    TomlNode(kind: tvkBoolean, boolVal: JSValueToBoolean(ctx, v))
  of kJSTypeNumber:
    var ex: JSValueRef = nil
    let f = JSValueToNumber(ctx, v, addr ex)
    if ex != nil:
      raise tomlErr("is not a number")
    if f != f or f == Inf or f == -Inf:
      raise tomlErr("null has no TOML representation")
    elif f == trunc(f) and abs(f) < 9223372036854775808.0:
      TomlNode(kind: tvkInteger, intVal: int64(f))
    else:
      TomlNode(kind: tvkFloat, floatVal: f)
  else:
    raise tomlErr("has an unsupported value")

proc jsToTomlNode(ctx: JSContextRef; v: JSValueRef; depth: int): TomlNode =
  ## Live JS value -> TomlNode in one walk, feeding dumpTOML directly.
  ## Null raises (TOML has no null); JSON holes follow bridge rules.
  if v == nil:
    raise tomlErr("is null")
  if depth > maxDumpDepth:
    raise tomlErr("is too deeply nested or circular")
  if JSValueGetType(ctx, v) == kJSTypeNull:
    raise tomlErr("null has no TOML representation")
  if jsSkipped(ctx, v):
    raise tomlErr("value is not TOML-serializable")
  case JSValueGetType(ctx, v)
  of kJSTypeObject:
    if JSValueIsArray(ctx, v):
      var ex: JSValueRef = nil
      let lenKey = newJSString("length")
      defer: JSStringRelease(lenKey)
      let lenV = JSObjectGetProperty(ctx, v, lenKey, addr ex)
      if ex != nil or lenV == nil:
        raise tomlErr("has an unreadable length")
      var ex2: JSValueRef = nil
      let n = int(JSValueToNumber(ctx, lenV, addr ex2))
      if ex2 != nil or n < 0:
        raise tomlErr("has an unreadable length")
      result = TomlNode(kind: tvkArray, arrayVal: @[], tableArray: false)
      for idx in 0 ..< n:
        var eEx: JSValueRef = nil
        let item = JSObjectGetPropertyAtIndex(ctx, v, cuint(idx), addr eEx)
        if eEx != nil or item == nil:
          raise tomlErr("has an unreadable index " & $idx)
        if jsSkipped(ctx, item):
          raise tomlErr("null has no TOML representation")
        result.arrayVal.add(jsToTomlNode(ctx, item, depth + 1))
    else:
      let names = JSObjectCopyPropertyNames(ctx, v)
      if names == nil:
        raise tomlErr("has unreadable properties")
      defer: JSPropertyNameArrayRelease(names)
      result = TomlNode(kind: tvkTable,
        tableVal: newOrderedTable[string, TomlNode]())
      let count = int(JSPropertyNameArrayGetCount(names))
      for idx in 0 ..< count:
        let jsName =
          JSPropertyNameArrayGetNameAtIndex(names, csize_t(idx))
        let key = $jsName
        var pEx: JSValueRef = nil
        let prop = JSObjectGetProperty(ctx, v, jsName, addr pEx)
        if pEx != nil or prop == nil:
          raise tomlErr("has an unreadable property \"" & key & "\"")
        if jsSkipped(ctx, prop):
          continue
        result.tableVal[key] = jsToTomlNode(ctx, prop, depth + 1)
  of kJSTypeBigInt:
    raise tomlErr("value is not TOML-serializable")
  else:
    result = jsScalarToToml(ctx, v)

## Builds the std/toml namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## toml.parse(text) -> object (document root must be a table)
      try:
        let j = tomlNodeToJS(ctx, parseTOML(text))
        if j == nil:
          throwError(ctx, "parse: could not convert result to JS",
            exception)
          return nil
        j
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify(value: JSValueRef):
      ## toml.stringify(obj) -> string
      try:
        let node = jsToTomlNode(ctx, value, 0)
        if node == nil or node.kind != tvkTable:
          throwError(ctx, "stringify: TOML document root must be an object",
            exception)
          return nil
        toJS(ctx, dumpTOML(node))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
