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

import std/options

import javascriptcore

import pkg/mimedb

import ../bridge

## Builds the std/mimetype namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn lookup(ext: string):
      ## mimetype.lookup(ext) -> MIME type string or null
      let t = getMimeType(ext)
      if t.isSome:
        toJS(ctx, t.get())
      else:
        JSValueMakeNull(ctx)

    module.registerFn info(mimeType: string):
      ## mimetype.info(type) -> {source, extensions, compressible} or null
      let i = getMimeInfo(mimeType)
      if i.isSome:
        let info = i.get()
        let opt = some(info)
        let obj = newObject(ctx)
        if not setPropChecked(ctx, obj, "source",
            toJS(ctx, $opt.getSource()), "info", exception):
          return nil
        if not setPropChecked(ctx, obj, "compressible",
            toJS(ctx, opt.isCompressible()), "info", exception):
          return nil
        var vals: seq[JSValueRef] = @[]
        let known = opt.getExtensions()
        if known.isSome:
          for e in known.get():
            vals.add(toJS(ctx, e))
        let exts = makeJSArray(ctx, vals)
        if exts == nil:
          throwError(ctx, "info: could not convert result to JS",
            exception)
          return nil
        if not setPropChecked(ctx, obj, "extensions", exts, "info",
            exception):
          return nil
        obj
      else:
        JSValueMakeNull(ctx)

    module.registerFn isExtension(ext: string):
      ## mimetype.isExtension(ext) -> bool
      toJS(ctx, isExtension(ext))

    module.registerFn has(mimeType: string):
      ## mimetype.has(type) -> bool
      toJS(ctx, hasMimeType(mimeType))
