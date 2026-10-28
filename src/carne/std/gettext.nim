# Carne std/gettext: .po parsing and translation via openparser.
#
#   const gettext = require("std/gettext");
#   gettext.parse(text)
#     -> {headers: {...}, entries: [{msgid, msgstr: [...], ...}]}
#   gettext.translate(text, msgid[, msgctxt]) -> translated string
#   gettext.ntranslate(text, singular, plural, n) -> plural form
#
# Entries carry msgid, msgstr[], and msgidPlural/msgctxt/fuzzy only when
# present. Obsolete entries are skipped; untranslated ids fall back to
# the msgid. openparser's reader is MemFile-based, so input goes through
# a temp file (same bridge as std/csv). .mo is out of scope in v1
# (binary input).

import std/[json, os, strutils, tables]

import javascriptcore

import pkg/openparser/gettext/po

import ../bridge

proc openTemp(text, name: string; ctx: JSContextRef;
    exception: ptr JSValueRef; tmp: var string;
    cat: var PoCatalog): bool =
  ## Writes text to a temp file and opens it. False + JS throw on failure.
  ## Callers must close(cat) and removeFile(tmp) when done: close unmaps
  ## the file, so all decoding happens before it.
  tmp = getTempDir() / "carne_gettext_parse.tmp"
  try:
    writeFile(tmp, text)
  except IOError as e:
    throwError(ctx, name & ": " & e.msg, exception)
    return false
  except OSError as e:
    throwError(ctx, name & ": " & e.msg, exception)
    return false
  try:
    cat = openPoCatalog(tmp)
  except CatchableError as e:
    try: removeFile(tmp)
    except OSError: discard
    throwError(ctx, name & ": " & e.msg, exception)
    return false
  true

proc closeTemp(tmp: string; cat: PoCatalog) =
  close(cat)
  try: removeFile(tmp)
  except OSError: discard

proc entryToJson(cat: PoCatalog; e: PoEntry): JsonNode =
  result = newJObject()
  result["msgid"] = %decodeField(cat, e.msgid)
  let plural = decodeField(cat, e.msgidPlural)
  if plural.len > 0:
    result["msgidPlural"] = %plural
  let ctx = decodeField(cat, e.msgctxt)
  if ctx.len > 0:
    result["msgctxt"] = %ctx
  var forms = newJArray()
  for m in e.msgstr:
    forms.add(%decodeMsgStr(cat, e, m.idx))
  result["msgstr"] = forms
  var fuzzy = false
  for c in e.comments:
    if c.kind == pckFlag and "fuzzy" in toString(cat, c.text):
      fuzzy = true
      break
  if fuzzy:
    result["fuzzy"] = %true

## Builds the std/gettext namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse:
      ## gettext.parse(text) -> {headers, entries}
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      var tmp = ""
      var cat: PoCatalog
      if not openTemp(text, "parse", ctx, exception, tmp, cat):
        return nil
      try:
        var headers = newJObject()
        for k, v in parsePoHeaders(cat):
          headers[k] = %v
        var entries = newJArray()
        for e in cat.entries:
          if e.obsolete:
            continue
          if decodeField(cat, e.msgid).len == 0:
            continue
          entries.add(entryToJson(cat, e))
        let node = %*{"headers": headers, "entries": entries}
        closeTemp(tmp, cat)
        returnJson(ctx, node, "parse", exception)
      except CatchableError as e:
        closeTemp(tmp, cat)
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn translate:
      ## gettext.translate(text, msgid[, msgctxt]) -> string
      if not checkArity(argumentCount, 2, 3, "translate", ctx, exception):
        return nil
      var text, msgid, msgctxt: string
      if not strArg(ctx, args, 0, "translate", exception, text):
        return nil
      if not strArg(ctx, args, 1, "translate", exception, msgid):
        return nil
      if int(argumentCount) == 3 and
          not strArg(ctx, args, 2, "translate", exception, msgctxt):
        return nil
      var tmp = ""
      var cat: PoCatalog
      if not openTemp(text, "translate", ctx, exception, tmp, cat):
        return nil
      try:
        let s = translate(compilePo(cat), msgid, msgctxt)
        closeTemp(tmp, cat)
        toJS(ctx, s)
      except CatchableError as e:
        closeTemp(tmp, cat)
        throwError(ctx, "translate: " & e.msg, exception)
        nil

    module.registerFn ntranslate:
      ## gettext.ntranslate(text, singular, plural, n) -> string
      if not checkArity(argumentCount, 4, 4, "ntranslate", ctx, exception):
        return nil
      var text, singular, plural: string
      var n = 0.0
      if not strArg(ctx, args, 0, "ntranslate", exception, text):
        return nil
      if not strArg(ctx, args, 1, "ntranslate", exception, singular):
        return nil
      if not strArg(ctx, args, 2, "ntranslate", exception, plural):
        return nil
      if not numArg(ctx, args, 3, "ntranslate", exception, n):
        return nil
      var tmp = ""
      var cat: PoCatalog
      if not openTemp(text, "ntranslate", ctx, exception, tmp, cat):
        return nil
      try:
        let s = ntranslate(compilePo(cat), singular, plural, int(n))
        closeTemp(tmp, cat)
        toJS(ctx, s)
      except CatchableError as e:
        closeTemp(tmp, cat)
        throwError(ctx, "ntranslate: " & e.msg, exception)
        nil
