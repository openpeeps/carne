# Carne std/vcard: vCard contact parsing via openparser.
#
#   const vcard = require("std/vcard");
#   vcard.parse(text) -> contact[] (one object per VCARD)
#
# Parse-only in v1: contact objects are plain data (absent options stay
# absent), but there is no object-to-vCard builder yet.

import std/options

import javascriptcore

import pkg/openparser/vcard

import ../bridge



proc strsToJS(ctx: JSContextRef; strs: seq[string]): JSValueRef =
  var vals: seq[JSValueRef] = @[]
  for s in strs:
    vals.add(toJS(ctx, s))
  makeJSArray(ctx, vals)

proc paramsToJS(ctx: JSContextRef; params: seq[VCardParam];
    fname: string; exception: ptr JSValueRef): JSValueRef =
  var vals: seq[JSValueRef] = @[]
  for p in params:
    var vvals: seq[JSValueRef] = @[]
    for v in p.values:
      vvals.add(toJS(ctx, v))
    let values = makeJSArray(ctx, vvals)
    if values == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "name", toJS(ctx, p.name), fname,
        exception):
      return nil
    if not setPropChecked(ctx, obj, "values", values, fname, exception):
      return nil
    vals.add(obj)
  makeJSArray(ctx, vals)

proc commonToJS(ctx: JSContextRef; obj: JSObjectRef; types: seq[string];
    pref: Option[int]; altId: Option[string]; params: seq[VCardParam];
    fname: string; exception: ptr JSValueRef): bool =
  let t = strsToJS(ctx, types)
  if t == nil:
    throwError(ctx, fname & ": could not convert result to JS",
      exception)
    return false
  if not setPropChecked(ctx, obj, "types", t, fname, exception):
    return false
  if not optSetInt(ctx, obj, "pref", pref, fname, exception):
    return false
  if not optSetStr(ctx, obj, "altId", altId, fname, exception):
    return false
  if params.len > 0:
    let p = paramsToJS(ctx, params, fname, exception)
    if p == nil:
      return false
    if not setPropChecked(ctx, obj, "params", p, fname, exception):
      return false
  true

proc valueToJS(ctx: JSContextRef; value: string; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "value", toJS(ctx, value), fname,
      exception):
    return nil
  obj

proc photoToJS(ctx: JSContextRef; p: VCardPhoto; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = valueToJS(ctx, p.value, fname, exception)
  if obj == nil:
    return nil
  if not optSetStr(ctx, obj, "mediaType", p.mediaType, fname, exception):
    return nil
  if not commonToJS(ctx, obj, p.types, p.pref, p.altId, p.params,
      fname, exception):
    return nil
  obj

proc adrToJS(ctx: JSContextRef; a: VCardAdr; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  for (key, val) in [("poBox", a.poBox), ("ext", a.ext),
      ("street", a.street), ("locality", a.locality),
      ("region", a.region), ("postal", a.postal),
      ("country", a.country)]:
    if not setPropChecked(ctx, obj, key, toJS(ctx, val), fname,
        exception):
      return nil
  if not optSetStr(ctx, obj, "label", a.label, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "geo", a.geo, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "tz", a.tz, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "altId", a.altId, fname, exception):
    return nil
  if not optSetInt(ctx, obj, "pref", a.pref, fname, exception):
    return nil
  let t = strsToJS(ctx, a.types)
  if t == nil:
    throwError(ctx, fname & ": could not convert result to JS",
      exception)
    return nil
  if not setPropChecked(ctx, obj, "types", t, fname, exception):
    return nil
  if a.params.len > 0:
    let p = paramsToJS(ctx, a.params, fname, exception)
    if p == nil:
      return nil
    if not setPropChecked(ctx, obj, "params", p, fname, exception):
      return nil
  obj

proc labeledToJS(ctx: JSContextRef; value: string; label: Option[string];
    types: seq[string]; pref: Option[int]; altId: Option[string];
    params: seq[VCardParam]; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  ## value + label + common tail (tel, url shapes).
  let obj = valueToJS(ctx, value, fname, exception)
  if obj == nil:
    return nil
  if not optSetStr(ctx, obj, "label", label, fname, exception):
    return nil
  if not commonToJS(ctx, obj, types, pref, altId, params, fname,
      exception):
    return nil
  obj

proc plainToJS(ctx: JSContextRef; value: string; types: seq[string];
    pref: Option[int]; altId: Option[string]; params: seq[VCardParam];
    fname: string; exception: ptr JSValueRef): JSValueRef =
  ## value + common tail, no label (email, impp, lang shapes).
  let obj = valueToJS(ctx, value, fname, exception)
  if obj == nil:
    return nil
  if not commonToJS(ctx, obj, types, pref, altId, params, fname,
      exception):
    return nil
  obj

proc telToJS(ctx: JSContextRef; t: VCardTel; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  labeledToJS(ctx, t.value, t.label, t.types, t.pref, t.altId, t.params,
    fname, exception)

proc emailToJS(ctx: JSContextRef; e: VCardEmail; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  plainToJS(ctx, e.value, e.types, e.pref, e.altId, e.params, fname,
    exception)

proc imppToJS(ctx: JSContextRef; i: VCardImpp; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  plainToJS(ctx, i.value, i.types, i.pref, i.altId, i.params, fname,
    exception)

proc langToJS(ctx: JSContextRef; l: VCardLang; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  plainToJS(ctx, l.value, l.types, l.pref, l.altId, l.params, fname,
    exception)

proc urlToJS(ctx: JSContextRef; u: VCardUrl; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  labeledToJS(ctx, u.value, u.label, u.types, u.pref, u.altId, u.params,
    fname, exception)

proc memberToJS(ctx: JSContextRef; m: VCardMember; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = valueToJS(ctx, m.value, fname, exception)
  if obj == nil:
    return nil
  if not optSetInt(ctx, obj, "pref", m.pref, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "altId", m.altId, fname, exception):
    return nil
  if m.params.len > 0:
    let p = paramsToJS(ctx, m.params, fname, exception)
    if p == nil:
      return nil
    if not setPropChecked(ctx, obj, "params", p, fname, exception):
      return nil
  obj

proc relatedToJS(ctx: JSContextRef; r: VCardRelated; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = valueToJS(ctx, r.value, fname, exception)
  if obj == nil:
    return nil
  if not optSetStr(ctx, obj, "relType", r.relType, fname, exception):
    return nil
  if not commonToJS(ctx, obj, r.types, r.pref, r.altId, r.params,
      fname, exception):
    return nil
  obj

proc datePropToJS(ctx: JSContextRef; d: VCardDateProp; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "value", toJS(ctx, d.value), fname,
      exception):
    return nil
  if not setPropChecked(ctx, obj, "valueType", toJS(ctx, d.valueType),
      fname, exception):
    return nil
  if not optSetStr(ctx, obj, "altId", d.altId, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "calscale", d.calscale, fname, exception):
    return nil
  if d.params.len > 0:
    let p = paramsToJS(ctx, d.params, fname, exception)
    if p == nil:
      return nil
    if not setPropChecked(ctx, obj, "params", p, fname, exception):
      return nil
  obj

proc kindToJS(ctx: JSContextRef; k: VCardKindValue): JSValueRef =
  case k.kind
  of vkIndividual: toJS(ctx, "individual")
  of vkGroup: toJS(ctx, "group")
  of vkOrg: toJS(ctx, "org")
  of vkLocation: toJS(ctx, "location")
  of vkApplication: toJS(ctx, "application")
  of vkCustom: toJS(ctx, k.custom)

proc seqToJS[T](ctx: JSContextRef; items: seq[T]; fname: string;
    exception: ptr JSValueRef;
    conv: proc(ctx: JSContextRef; x: T; fname: string;
      exception: ptr JSValueRef): JSValueRef): JSValueRef =
  var vals: seq[JSValueRef] = @[]
  for item in items:
    let j = conv(ctx, item, fname, exception)
    if j == nil:
      return nil
    vals.add(j)
  let arr = makeJSArray(ctx, vals)
  if arr == nil:
    throwError(ctx, fname & ": could not convert result to JS",
      exception)
    return nil
  arr

proc cardToJS(ctx: JSContextRef; c: VCard; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "version", toJS(ctx, $c.version),
      fname, exception):
    return nil
  if not setPropChecked(ctx, obj, "fn", toJS(ctx, c.fn), fname,
      exception):
    return nil
  if c.n.isSome:
    let n = c.n.get()
    let nobj = newObject(ctx)
    for (key, val) in [("family", n.family), ("given", n.given),
        ("additional", n.additional), ("prefix", n.prefix),
        ("suffix", n.suffix)]:
      if not setPropChecked(ctx, nobj, key, toJS(ctx, val), fname,
          exception):
        return nil
    if not setPropChecked(ctx, obj, "n", nobj, fname, exception):
      return nil
  template setSeq(key: string; items, conv: untyped): untyped =
    let arrVal = seqToJS(ctx, items, fname, exception, conv)
    if arrVal == nil:
      return nil
    if not setPropChecked(ctx, obj, key, arrVal, fname, exception):
      return nil
  template setStrs(key: string; items: seq[string]): untyped =
    let arrVal = strsToJS(ctx, items)
    if arrVal == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, key, arrVal, fname, exception):
      return nil
  setStrs("nicknames", c.nicknames)
  setSeq("photos", c.photos, photoToJS)
  if c.bday.isSome:
    let b = datePropToJS(ctx, c.bday.get(), fname, exception)
    if b == nil:
      return nil
    if not setPropChecked(ctx, obj, "bday", b, fname, exception):
      return nil
  if c.anniversary.isSome:
    let a = datePropToJS(ctx, c.anniversary.get(), fname, exception)
    if a == nil:
      return nil
    if not setPropChecked(ctx, obj, "anniversary", a, fname,
        exception):
      return nil
  if c.gender.isSome:
    let g = c.gender.get()
    let gobj = newObject(ctx)
    if not setPropChecked(ctx, gobj, "sex", toJS(ctx, g.sex), fname,
        exception):
      return nil
    if not setPropChecked(ctx, gobj, "identity", toJS(ctx, g.identity),
        fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "gender", gobj, fname, exception):
      return nil
  setSeq("adrs", c.adrs, adrToJS)
  setSeq("tels", c.tels, telToJS)
  setSeq("emails", c.emails, emailToJS)
  setSeq("impps", c.impps, imppToJS)
  setSeq("langs", c.langs, langToJS)
  if not optSetStr(ctx, obj, "tz", c.tz, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "geo", c.geo, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "title", c.title, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "role", c.role, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "logo", c.logo, fname, exception):
    return nil
  if c.org.isSome:
    let o = c.org.get()
    let oobj = newObject(ctx)
    if not setPropChecked(ctx, oobj, "name", toJS(ctx, o.name), fname,
        exception):
      return nil
    let units = strsToJS(ctx, o.units)
    if units == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, oobj, "units", units, fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "org", oobj, fname, exception):
      return nil
  setSeq("members", c.members, memberToJS)
  setSeq("related", c.related, relatedToJS)
  setStrs("categories", c.categories)
  if not optSetStr(ctx, obj, "note", c.note, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "prodId", c.prodId, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "rev", c.rev, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "sortString", c.sortString, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "sound", c.sound, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "uid", c.uid, fname, exception):
    return nil
  if c.kind.isSome:
    if not setPropChecked(ctx, obj, "kind",
        kindToJS(ctx, c.kind.get()), fname, exception):
      return nil
  var pidVals: seq[JSValueRef] = @[]
  for pid in c.clientPidMaps:
    let pobj = newObject(ctx)
    if not setPropChecked(ctx, pobj, "pid", toJS(ctx, pid.pid), fname,
        exception):
      return nil
    if not setPropChecked(ctx, pobj, "uri", toJS(ctx, pid.uri), fname,
        exception):
      return nil
    pidVals.add(pobj)
  let pids = makeJSArray(ctx, pidVals)
  if pids == nil:
    throwError(ctx, fname & ": could not convert result to JS",
      exception)
    return nil
  if not setPropChecked(ctx, obj, "clientPidMaps", pids, fname,
      exception):
    return nil
  setSeq("urls", c.urls, urlToJS)
  if not optSetStr(ctx, obj, "key", c.key, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "fbUrl", c.fbUrl, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "calAdrUri", c.calAdrUri, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "calUri", c.calUri, fname, exception):
    return nil
  setStrs("xml", c.xml)
  if c.extraProps.len > 0:
    var evals: seq[JSValueRef] = @[]
    for p in c.extraProps:
      let pobj = newObject(ctx)
      if not setPropChecked(ctx, pobj, "group", toJS(ctx, p.group),
          fname, exception):
        return nil
      if not setPropChecked(ctx, pobj, "name", toJS(ctx, p.name),
          fname, exception):
        return nil
      let prm = paramsToJS(ctx, p.params, fname, exception)
      if prm == nil:
        return nil
      if not setPropChecked(ctx, pobj, "params", prm, fname, exception):
        return nil
      if not setPropChecked(ctx, pobj, "value", toJS(ctx, p.value),
          fname, exception):
        return nil
      evals.add(pobj)
    let extra = makeJSArray(ctx, evals)
    if extra == nil:
      throwError(ctx, fname & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "extraProps", extra, fname,
        exception):
      return nil
  obj

## Builds the std/vcard namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## vcard.parse(text) -> contact[] (one object per VCARD)
      try:
        var vals: seq[JSValueRef] = @[]
        for c in parseVCards(text):
          let j = cardToJS(ctx, c, "parse", exception)
          if j == nil:
            return nil
          vals.add(j)
        let arr = makeJSArray(ctx, vals)
        if arr == nil:
          throwError(ctx, "parse: could not convert result to JS",
            exception)
          return nil
        arr
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil
