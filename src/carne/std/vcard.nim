# Carne std/vcard: vCard contact parsing via openparser.
#
#   const vcard = require("std/vcard");
#   vcard.parse(text) -> contact[] (one object per VCARD)
#
# Parse-only in v1: contact objects are plain data (absent options stay
# absent), but there is no object-to-vCard builder yet.

import std/[json, options]

import javascriptcore

import pkg/openparser/vcard

import ../bridge

proc optStr(obj: JsonNode; key: string; v: Option[string]) =
  if v.isSome:
    obj[key] = %v.get()

proc optInt(obj: JsonNode; key: string; v: Option[int]) =
  if v.isSome:
    obj[key] = %v.get()

proc strsToJson(strs: seq[string]): JsonNode =
  result = newJArray()
  for s in strs:
    result.add(%s)

proc paramsToJson(params: seq[VCardParam]): JsonNode =
  result = newJArray()
  for p in params:
    var values = newJArray()
    for v in p.values:
      values.add(%v)
    result.add(%*{"name": p.name, "values": values})

proc commonToJson(obj: JsonNode; types: seq[string]; pref: Option[int];
    altId: Option[string]; params: seq[VCardParam]) =
  obj["types"] = strsToJson(types)
  optInt(obj, "pref", pref)
  optStr(obj, "altId", altId)
  if params.len > 0:
    obj["params"] = paramsToJson(params)

proc photoToJson(p: VCardPhoto): JsonNode =
  result = %*{"value": p.value}
  optStr(result, "mediaType", p.mediaType)
  commonToJson(result, p.types, p.pref, p.altId, p.params)

proc adrToJson(a: VCardAdr): JsonNode =
  result = %*{
    "poBox": a.poBox, "ext": a.ext, "street": a.street,
    "locality": a.locality, "region": a.region, "postal": a.postal,
    "country": a.country}
  optStr(result, "label", a.label)
  optStr(result, "geo", a.geo)
  optStr(result, "tz", a.tz)
  optStr(result, "altId", a.altId)
  optInt(result, "pref", a.pref)
  result["types"] = strsToJson(a.types)
  if a.params.len > 0:
    result["params"] = paramsToJson(a.params)

proc telToJson(t: VCardTel): JsonNode =
  result = %*{"value": t.value}
  optStr(result, "label", t.label)
  commonToJson(result, t.types, t.pref, t.altId, t.params)

proc emailToJson(e: VCardEmail): JsonNode =
  result = %*{"value": e.value}
  commonToJson(result, e.types, e.pref, e.altId, e.params)

proc imppToJson(i: VCardImpp): JsonNode =
  result = %*{"value": i.value}
  commonToJson(result, i.types, i.pref, i.altId, i.params)

proc langToJson(l: VCardLang): JsonNode =
  result = %*{"value": l.value}
  commonToJson(result, l.types, l.pref, l.altId, l.params)

proc urlToJson(u: VCardUrl): JsonNode =
  result = %*{"value": u.value}
  optStr(result, "label", u.label)
  commonToJson(result, u.types, u.pref, u.altId, u.params)

proc memberToJson(m: VCardMember): JsonNode =
  result = %*{"value": m.value}
  optInt(result, "pref", m.pref)
  optStr(result, "altId", m.altId)
  if m.params.len > 0:
    result["params"] = paramsToJson(m.params)

proc relatedToJson(r: VCardRelated): JsonNode =
  result = %*{"value": r.value}
  optStr(result, "relType", r.relType)
  commonToJson(result, r.types, r.pref, r.altId, r.params)

proc datePropToJson(d: VCardDateProp): JsonNode =
  result = %*{"value": d.value, "valueType": d.valueType}
  optStr(result, "altId", d.altId)
  optStr(result, "calscale", d.calscale)
  if d.params.len > 0:
    result["params"] = paramsToJson(d.params)

proc kindToJson(k: VCardKindValue): JsonNode =
  case k.kind
  of vkIndividual: %"individual"
  of vkGroup: %"group"
  of vkOrg: %"org"
  of vkLocation: %"location"
  of vkApplication: %"application"
  of vkCustom: %k.custom

proc seqToJson[T](items: seq[T]; conv: proc(x: T): JsonNode): JsonNode =
  result = newJArray()
  for item in items:
    result.add(conv(item))

proc cardToJson(c: VCard): JsonNode =
  result = %*{"version": $c.version, "fn": c.fn}
  if c.n.isSome:
    let n = c.n.get()
    result["n"] = %*{
      "family": n.family, "given": n.given, "additional": n.additional,
      "prefix": n.prefix, "suffix": n.suffix}
  result["nicknames"] = strsToJson(c.nicknames)
  result["photos"] = seqToJson(c.photos, photoToJson)
  if c.bday.isSome:
    result["bday"] = datePropToJson(c.bday.get())
  if c.anniversary.isSome:
    result["anniversary"] = datePropToJson(c.anniversary.get())
  if c.gender.isSome:
    let g = c.gender.get()
    result["gender"] = %*{"sex": g.sex, "identity": g.identity}
  result["adrs"] = seqToJson(c.adrs, adrToJson)
  result["tels"] = seqToJson(c.tels, telToJson)
  result["emails"] = seqToJson(c.emails, emailToJson)
  result["impps"] = seqToJson(c.impps, imppToJson)
  result["langs"] = seqToJson(c.langs, langToJson)
  optStr(result, "tz", c.tz)
  optStr(result, "geo", c.geo)
  optStr(result, "title", c.title)
  optStr(result, "role", c.role)
  optStr(result, "logo", c.logo)
  if c.org.isSome:
    let o = c.org.get()
    result["org"] = %*{"name": o.name, "units": strsToJson(o.units)}
  result["members"] = seqToJson(c.members, memberToJson)
  result["related"] = seqToJson(c.related, relatedToJson)
  result["categories"] = strsToJson(c.categories)
  optStr(result, "note", c.note)
  optStr(result, "prodId", c.prodId)
  optStr(result, "rev", c.rev)
  optStr(result, "sortString", c.sortString)
  optStr(result, "sound", c.sound)
  optStr(result, "uid", c.uid)
  if c.kind.isSome:
    result["kind"] = kindToJson(c.kind.get())
  var pids = newJArray()
  for pid in c.clientPidMaps:
    pids.add(%*{"pid": pid.pid, "uri": pid.uri})
  result["clientPidMaps"] = pids
  result["urls"] = seqToJson(c.urls, urlToJson)
  optStr(result, "key", c.key)
  optStr(result, "fbUrl", c.fbUrl)
  optStr(result, "calAdrUri", c.calAdrUri)
  optStr(result, "calUri", c.calUri)
  result["xml"] = strsToJson(c.xml)
  if c.extraProps.len > 0:
    var extra = newJArray()
    for p in c.extraProps:
      extra.add(%*{"group": p.group, "name": p.name,
        "params": paramsToJson(p.params), "value": p.value})
    result["extraProps"] = extra

## Builds the std/vcard namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse:
      ## vcard.parse(text) -> contact[] (one object per VCARD)
      if not checkArity(argumentCount, 1, 1, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      try:
        let arr = newJArray()
        for c in parseVCards(text):
          arr.add(cardToJson(c))
        returnJson(ctx, arr, "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil
