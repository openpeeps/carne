# Carne std/yaml: YAML parsing and serialization via openparser.
#
#   const yaml = require("std/yaml");
#   yaml.parse(text)      -> value (objects, arrays, scalars)
#   yaml.stringify(value) -> string (single YAML document)
#
# Single-document in v1: trailing documents after `---` are ignored.

import std/[json, tables]

import javascriptcore

import pkg/openparser/yaml

import ../bridge

proc yamlToJson(n: YamlNode): JsonNode =
  case n.kind
  of yamlNull:
    result = newJNull()
  of yamlBoolean:
    result = %n.boolValue
  of yamlInteger:
    result = %n.intValue
  of yamlFloat:
    result = %n.floatValue
  of yamlString:
    result = %n.strValue
  of yamlObject:
    result = newJObject()
    for k, v in n.objValue:
      result[k] = yamlToJson(v)
  of yamlArray:
    result = newJArray()
    for item in n.arrValue:
      result.add(yamlToJson(item))

## Builds the std/yaml namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse:
      ## yaml.parse(text) -> value (objects, arrays, scalars)
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      try:
        returnJson(ctx, yamlToJson(parseYAMLNode(text)), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify:
      ## yaml.stringify(value) -> string (single YAML document)
      if not checkArity(argumentCount, 1, 1, "stringify", ctx, exception):
        return nil
      var err = ""
      let node = jsToJson(ctx, args[0], err)
      if node == nil:
        throwError(ctx, "stringify: " & err, exception)
        return nil
      try:
        toJS(ctx, dump(node))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
