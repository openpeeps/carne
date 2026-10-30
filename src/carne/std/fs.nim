# Carne std/fs: synchronous file system access.
#
#   const fs = require("std/fs");
#   fs.readFile(path)         -> string (throws on IOError)
#   fs.writeFile(path, data)  -> undefined
#   fs.exists(path)           -> bool (files and dirs)
#   fs.readDir(path)          -> string[] (entry names)
#   fs.mkdir(path)            -> undefined
#   fs.remove(path)           -> undefined (files only)

import std/os

import javascriptcore

import ../bridge

## Builds the std/fs namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn readFile(path: string):
      ## fs.readFile(path) -> string (throws on IOError)
      try:
        toJS(ctx, readFile(path))
      except IOError as e:
        throwError(ctx, "readFile: " & e.msg, exception)
        nil
      except OSError as e:
        throwError(ctx, "readFile: " & e.msg, exception)
        nil

    module.registerFn writeFile(path: string, data: string):
      ## fs.writeFile(path, data) -> undefined
      try:
        writeFile(path, data)
      except IOError as e:
        throwError(ctx, "writeFile: " & e.msg, exception)
        return nil
      except OSError as e:
        throwError(ctx, "writeFile: " & e.msg, exception)
        return nil
      JSValueMakeUndefined(ctx)

    module.registerFn exists(path: string):
      ## fs.exists(path) -> bool (files and dirs)
      toJS(ctx, fileExists(path) or dirExists(path))

    module.registerFn readDir(path: string):
      ## fs.readDir(path) -> string[] (entry names)
      var names: seq[string] = @[]
      try:
        for kind, entry in walkDir(path):
          names.add(entry.extractFilename())
      except OSError as e:
        throwError(ctx, "readDir: " & e.msg, exception)
        return nil
      var vals: seq[JSValueRef] = @[]
      for name in names:
        vals.add(toJS(ctx, name))
      var ex: JSValueRef = nil
      let arr =
        if vals.len > 0:
          JSObjectMakeArray(ctx, csize_t(vals.len), addr vals[0], addr ex)
        else:
          JSObjectMakeArray(ctx, 0, nil, addr ex)
      if arr == nil:
        if ex != nil and exception != nil:
          exception[] = ex
        return nil
      arr

    module.registerFn mkdir(path: string):
      ## fs.mkdir(path) -> undefined
      try:
        createDir(path)
      except OSError as e:
        throwError(ctx, "mkdir: " & e.msg, exception)
        return nil
      JSValueMakeUndefined(ctx)

    module.registerFn remove(path: string):
      ## fs.remove(path) -> undefined (files only)
      try:
        removeFile(path)
      except OSError as e:
        throwError(ctx, "remove: " & e.msg, exception)
        return nil
      JSValueMakeUndefined(ctx)
