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

    module.registerFn readFile:
      ## fs.readFile(path) -> string (throws on IOError)
      if not checkArity(argumentCount, 1, 1, "readFile", ctx, exception):
        return nil
      var path: string
      if not strArg(ctx, args, 0, "readFile", exception, path):
        return nil
      try:
        toJS(ctx, readFile(path))
      except IOError as e:
        throwError(ctx, "readFile: " & e.msg, exception)
        nil
      except OSError as e:
        throwError(ctx, "readFile: " & e.msg, exception)
        nil

    module.registerFn writeFile:
      ## fs.writeFile(path, data) -> undefined
      if not checkArity(argumentCount, 2, 2, "writeFile", ctx, exception):
        return nil
      var path, data: string
      if not strArg(ctx, args, 0, "writeFile", exception, path):
        return nil
      if not strArg(ctx, args, 1, "writeFile", exception, data):
        return nil
      try:
        writeFile(path, data)
      except IOError as e:
        throwError(ctx, "writeFile: " & e.msg, exception)
        return nil
      except OSError as e:
        throwError(ctx, "writeFile: " & e.msg, exception)
        return nil
      JSValueMakeUndefined(ctx)

    module.registerFn exists:
      ## fs.exists(path) -> bool (files and dirs)
      if not checkArity(argumentCount, 1, 1, "exists", ctx, exception):
        return nil
      var path: string
      if not strArg(ctx, args, 0, "exists", exception, path):
        return nil
      toJS(ctx, fileExists(path) or dirExists(path))

    module.registerFn readDir:
      ## fs.readDir(path) -> string[] (entry names)
      if not checkArity(argumentCount, 1, 1, "readDir", ctx, exception):
        return nil
      var path: string
      if not strArg(ctx, args, 0, "readDir", exception, path):
        return nil
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

    module.registerFn mkdir:
      ## fs.mkdir(path) -> undefined
      if not checkArity(argumentCount, 1, 1, "mkdir", ctx, exception):
        return nil
      var path: string
      if not strArg(ctx, args, 0, "mkdir", exception, path):
        return nil
      try:
        createDir(path)
      except OSError as e:
        throwError(ctx, "mkdir: " & e.msg, exception)
        return nil
      JSValueMakeUndefined(ctx)

    module.registerFn remove:
      ## fs.remove(path) -> undefined (files only)
      if not checkArity(argumentCount, 1, 1, "remove", ctx, exception):
        return nil
      var path: string
      if not strArg(ctx, args, 0, "remove", exception, path):
        return nil
      try:
        removeFile(path)
      except OSError as e:
        throwError(ctx, "remove: " & e.msg, exception)
        return nil
      JSValueMakeUndefined(ctx)
