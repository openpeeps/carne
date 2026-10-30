# Carne std/toml: TOML parsing and serialization via openparser.
#
#   const toml = require("std/toml");
#   toml.parse(text)      -> object (document root must be a table)
#   toml.stringify(obj)   -> string
#
# TOML datetimes surface as strings (the literal as written) and
# stringify back as TOML strings: the datetime type does not roundtrip.

import std/[json, tables]

import javascriptcore

import pkg/openparser/toml

import ../bridge

proc tomlToJson(n: TomlNode): JsonNode =
  case n.kind
  of tvkString:
    result = %n.strVal
  of tvkInteger:
    result = %n.intVal
  of tvkFloat:
    result = %n.floatVal
  of tvkBoolean:
    result = %n.boolVal
  of tvkDateTime:
    result = %n.dateRaw
  of tvkArray:
    result = newJArray()
    for item in n.arrayVal:
      result.add(tomlToJson(item))
  of tvkTable:
    result = newJObject()
    for k, v in n.tableVal:
      result[k] = tomlToJson(v)

proc jsonToTomlErr(msg: string): ref CatchableError =
  newException(CatchableError, msg)

proc jsonToToml(j: JsonNode): TomlNode =
  case j.kind
  of JString:
    TomlNode(kind: tvkString, strVal: j.getStr())
  of JInt:
    TomlNode(kind: tvkInteger, intVal: j.getBiggestInt())
  of JFloat:
    TomlNode(kind: tvkFloat, floatVal: j.getFloat())
  of JBool:
    TomlNode(kind: tvkBoolean, boolVal: j.getBool())
  of JNull:
    raise jsonToTomlErr("null has no TOML representation")
  of JArray:
    var items: seq[TomlNode] = @[]
    for item in j:
      items.add(jsonToToml(item))
    TomlNode(kind: tvkArray, arrayVal: items, tableArray: false)
  of JObject:
    var tbl = newOrderedTable[string, TomlNode]()
    for k, v in j.pairs:
      tbl[k] = jsonToToml(v)
    TomlNode(kind: tvkTable, tableVal: tbl)

## Builds the std/toml namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## toml.parse(text) -> object (document root must be a table)
      try:
        let doc = parseTOML(text)
        returnJson(ctx, tomlToJson(doc), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify(value: JSValueRef):
      ## toml.stringify(obj) -> string
      var err = ""
      let node = jsToJson(ctx, value, err)
      if node == nil:
        throwError(ctx, "stringify: " & err, exception)
        return nil
      if node.kind != JObject:
        throwError(ctx, "stringify: TOML document root must be an object",
          exception)
        return nil
      try:
        toJS(ctx, dumpTOML(jsonToToml(node)))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
