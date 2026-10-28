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

import std/[json, options, strutils]

import javascriptcore

import pkg/openparser/path

import ../bridge

proc optStr(obj: JsonNode; key: string; v: Option[string]) =
  if v.isSome:
    obj[key] = %v.get()

proc pathToJson(p: Path): JsonNode =
  result = newJObject()
  result["kind"] = %($p.kind)[2 .. ^1].toLowerAscii()
  if p.isLocal:
    optStr(result, "drive", p.drive)
    result["absolute"] = %p.isAbsolute
    var segs = newJArray()
    for s in p.segments:
      segs.add(%s)
    result["segments"] = segs
    optStr(result, "ext", p.localExt)
  else:
    result["scheme"] = %p.scheme
    if p.auth.isSome:
      let a = p.auth.get()
      result["user"] = %a.user
      optStr(result, "password", a.password)
    result["host"] = %p.host
    if p.port.isSome:
      result["port"] = %p.port.get()
    result["path"] = %p.path
    var segs = newJArray()
    for s in p.pathSegments:
      segs.add(%s)
    result["segments"] = segs
    var q = newJArray()
    for param in p.query:
      q.add(%*{"key": param.key, "value": param.value})
    result["query"] = q
    optStr(result, "fragment", p.fragment)
    optStr(result, "ext", p.ext)

## Builds the std/path namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse:
      ## path.parse(text) -> local or network path object
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      try:
        returnJson(ctx, pathToJson(parsePath(text)), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil
