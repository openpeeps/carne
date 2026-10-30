# Carne std/plist: Apple property-list parsing via openparser.
#
#   const plist = require("std/plist");
#   plist.parse(data)      -> value (XML plists; binary plists arrive
#                             through std/fs readFile passthrough)
#   plist.stringify(value) -> string (XML plist)

import std/json

import javascriptcore

import pkg/openparser/plist

import ../bridge

## Builds the std/plist namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## plist.parse(data) -> value (XML or binary plist)
      try:
        returnJson(ctx, parsePlist(text), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify(value: JSValueRef):
      ## plist.stringify(value) -> string (XML plist)
      var err = ""
      let node = jsToJson(ctx, value, err)
      if node == nil:
        throwError(ctx, "stringify: " & err, exception)
        return nil
      try:
        toJS(ctx, toXmlPlist(node))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
