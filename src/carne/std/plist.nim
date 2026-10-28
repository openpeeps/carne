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

    module.registerFn parse:
      ## plist.parse(data) -> value (XML or binary plist)
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      try:
        returnJson(ctx, parsePlist(text), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify:
      ## plist.stringify(value) -> string (XML plist)
      if not checkArity(argumentCount, 1, 1, "stringify", ctx, exception):
        return nil
      var err = ""
      let node = jsToJson(ctx, args[0], err)
      if node == nil:
        throwError(ctx, "stringify: " & err, exception)
        return nil
      try:
        toJS(ctx, toXmlPlist(node))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
