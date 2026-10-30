# Carne std/mimetype: MIME type lookup via mimedb.
#
#   const mimetype = require("std/mimetype");
#   mimetype.lookup("html")       -> "text/html"
#   mimetype.lookup(".PNG")       -> "image/png"
#   mimetype.lookup("nope")       -> null
#   mimetype.info("text/html")
#     -> {source: "iana", extensions: ["html", "htm", "shtml"],
#         compressible: true}
#   mimetype.info("nope/x")       -> null
#   mimetype.isExtension("html")  -> true
#   mimetype.has("text/html")     -> true
#
# Lookup-only in v1. Extensions accept a leading dot and any case;
# MIME types match exactly (lowercase). `charset` is deferred until
# mimedb exposes a getter for it.

import std/[json, options]

import javascriptcore

import pkg/mimedb

import ../bridge

proc mimeInfoToJson(info: Mime): JsonNode =
  let opt = some(info)
  result = newJObject()
  result["source"] = %($opt.getSource())
  result["compressible"] = %opt.isCompressible()
  var exts = newJArray()
  let known = opt.getExtensions()
  if known.isSome:
    for e in known.get():
      exts.add(%e)
  result["extensions"] = exts

## Builds the std/mimetype namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn lookup(ext: string):
      ## mimetype.lookup(ext) -> MIME type string or null
      let t = getMimeType(ext)
      if t.isSome:
        toJS(ctx, t.get())
      else:
        returnJson(ctx, newJNull(), "lookup", exception)

    module.registerFn info(mimeType: string):
      ## mimetype.info(type) -> {source, extensions, compressible} or null
      let i = getMimeInfo(mimeType)
      if i.isSome:
        returnJson(ctx, mimeInfoToJson(i.get()), "info", exception)
      else:
        returnJson(ctx, newJNull(), "info", exception)

    module.registerFn isExtension(ext: string):
      ## mimetype.isExtension(ext) -> bool
      toJS(ctx, isExtension(ext))

    module.registerFn has(mimeType: string):
      ## mimetype.has(type) -> bool
      toJS(ctx, hasMimeType(mimeType))
