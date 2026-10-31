# Carne std/path: file-path and URL parsing via openparser.
#
#   const path = require("std/path");
#   path.parse("/a/b/c.txt")
#     -> {kind: "local", absolute: true, segments: ["a","b","c.txt"], ext: "txt"}
#   path.parse("https://user@host:8080/p?q=1#frag")
#     -> {kind: "web", scheme: "https", user: "user", host: "host",
#         port: 8080, path: "/p", segments: ["p"],
#         query: [{key: "q", value: "1"}], fragment: "frag"}
#
# Parse-only in v1. Absent options stay absent.

import std/[options, strutils]

import javascriptcore

import pkg/openparser/path

import ../bridge


proc pathToJS(ctx: JSContextRef; p: Path; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "kind",
      toJS(ctx, ($p.kind)[2 .. ^1].toLowerAscii()), fname, exception):
    return nil
  if p.isLocal:
    if not optSetStr(ctx, obj, "drive", p.drive, fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "absolute", toJS(ctx, p.isAbsolute),
        fname, exception):
      return nil
    var svals: seq[JSValueRef] = @[]
    for s in p.segments:
      svals.add(toJS(ctx, s))
    let segs = makeJSArray(ctx, svals)
    if segs == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "segments", segs, fname, exception):
      return nil
    if not optSetStr(ctx, obj, "ext", p.localExt, fname, exception):
      return nil
  else:
    if not setPropChecked(ctx, obj, "scheme", toJS(ctx, p.scheme),
        fname, exception):
      return nil
    if p.auth.isSome:
      let a = p.auth.get()
      if not setPropChecked(ctx, obj, "user", toJS(ctx, a.user), fname,
          exception):
        return nil
      if not optSetStr(ctx, obj, "password", a.password, fname,
          exception):
        return nil
    if not setPropChecked(ctx, obj, "host", toJS(ctx, p.host), fname,
        exception):
      return nil
    if p.port.isSome:
      if not setPropChecked(ctx, obj, "port", toJS(ctx, p.port.get()),
          fname, exception):
        return nil
    if not setPropChecked(ctx, obj, "path", toJS(ctx, p.path), fname,
        exception):
      return nil
    var svals: seq[JSValueRef] = @[]
    for s in p.pathSegments:
      svals.add(toJS(ctx, s))
    let segs = makeJSArray(ctx, svals)
    if segs == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "segments", segs, fname, exception):
      return nil
    var qvals: seq[JSValueRef] = @[]
    for param in p.query:
      let qobj = newObject(ctx)
      if not setPropChecked(ctx, qobj, "key", toJS(ctx, param.key),
          fname, exception):
        return nil
      if not setPropChecked(ctx, qobj, "value", toJS(ctx, param.value),
          fname, exception):
        return nil
      qvals.add(qobj)
    let q = makeJSArray(ctx, qvals)
    if q == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "query", q, fname, exception):
      return nil
    if not optSetStr(ctx, obj, "fragment", p.fragment, fname, exception):
      return nil
    if not optSetStr(ctx, obj, "ext", p.ext, fname, exception):
      return nil
  obj

## Builds the std/path namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## path.parse(text) -> local or network path object
      try:
        let j = pathToJS(ctx, parsePath(text), "parse", exception)
        if j == nil:
          throwError(ctx, "parse: could not convert result to JS",
            exception)
          return nil
        j
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil
