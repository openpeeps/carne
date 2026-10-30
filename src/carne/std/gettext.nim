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
    cat: var PoCatalog; docBlock = ""): bool =
  ## Writes text to a temp file and opens it. False + JS throw on failure.
  ## Callers must close(cat) and removeFile(tmp) when done: close unmaps
  ## the file, so all decoding happens before it.
  template oerr(msg: string): untyped =
    throwError(ctx,
      (if docBlock.len > 0: docBlock & "\n" else: "") & msg, exception)
  tmp = getTempDir() / "carne_gettext_parse.tmp"
  try:
    writeFile(tmp, text)
  except IOError as e:
    oerr(name & ": " & e.msg)
    return false
  except OSError as e:
    oerr(name & ": " & e.msg)
    return false
  try:
    cat = openPoCatalog(tmp)
  except CatchableError as e:
    try: removeFile(tmp)
    except OSError: discard
    oerr(name & ": " & e.msg)
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

    module.registerFn parse(text: string):
      ## gettext.parse(text) -> {headers, entries}
      var tmp = ""
      var cat: PoCatalog
      if not openTemp(text, "parse", ctx, exception, tmp, cat, docBlock):
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

    module.registerFn translate(text: string, msgid: string,
        msgctxt ?: string):
      ## gettext.translate(text, msgid[, msgctxt]) -> string
      var tmp = ""
      var cat: PoCatalog
      if not openTemp(text, "translate", ctx, exception, tmp, cat, docBlock):
        return nil
      try:
        let s = translate(compilePo(cat), msgid, msgctxt)
        closeTemp(tmp, cat)
        toJS(ctx, s)
      except CatchableError as e:
        closeTemp(tmp, cat)
        throwError(ctx, "translate: " & e.msg, exception)
        nil

    module.registerFn ntranslate(text: string, singular: string,
        plural: string, n: int64):
      ## gettext.ntranslate(text, singular, plural, n) -> string
      var tmp = ""
      var cat: PoCatalog
      if not openTemp(text, "ntranslate", ctx, exception, tmp, cat, docBlock):
        return nil
      try:
        let s = ntranslate(compilePo(cat), singular, plural, int(n))
        closeTemp(tmp, cat)
        toJS(ctx, s)
      except CatchableError as e:
        closeTemp(tmp, cat)
        throwError(ctx, "ntranslate: " & e.msg, exception)
        nil
