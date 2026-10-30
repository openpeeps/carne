# Carne std/dotenv: `.env` file parsing via openparser.
#
#   const dotenv = require("std/dotenv");
#   dotenv.parse(text)            -> object (with variable expansion applied)
#   dotenv.load([path][, override]) -> undefined (writes into process env,
#                                     visible through std/env; defaults to ".env")

import std/[json, tables]

import javascriptcore

import pkg/openparser/dotenv

import ../bridge

## Builds the std/dotenv namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## dotenv.parse(text) -> object (with variable expansion applied)
      try:
        # Same expansion loadDotenv applies, collected into an object
        # instead of the process environment.
        var local = initTable[string, string]()
        var cmdCache = initTable[string, string]()
        let obj = newJObject()
        for e in parseEnv(text):
          let v =
            if e.expand: expandValue(e.value, local, cmdCache)
            else: e.value
          local[e.key] = v
          obj[e.key] = %v
        returnJson(ctx, obj, "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn load(path: default(string, ".env"),
        override ?: bool):
      ## dotenv.load([path][, override]) -> undefined (writes into process env)
      try:
        loadDotenv(path, override)
      except CatchableError as e:
        throwError(ctx, "load: " & e.msg, exception)
        return nil
      JSValueMakeUndefined(ctx)
