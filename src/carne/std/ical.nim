# Carne std/ical: iCalendar parsing and serialization via openparser.
#
#   const ical = require("std/ical");
#   ical.parse(text)      -> {events, todos, journals, timezones, others}
#   ical.stringify(cal)   -> string (a VCALENDAR document)
#
# Shape: absent options stay absent, sequences are always present.
# Dates serialize as {value: "20260101T100000Z", tzid?}, durations as
# "P1DT2H" strings, persons as {uri, cn?, params?}. Unknown properties
# ride along in extraProps and survive the roundtrip.
#
# stringify reads known keys only: unknown input keys are ignored, so
# a stray reference cycle hiding behind an unknown key cannot hang it
# (all followed paths are depth-capped).

import std/[math, options]

import javascriptcore

import pkg/openparser/ical

import ../bridge

proc icalErr(msg: string): ref CatchableError =
  newException(CatchableError, msg)

# -- typed model -> live JS ------------------------------------------------

proc optSetDt(ctx: JSContextRef; obj: JSObjectRef; key: string;
    v: Option[IcalDt]; fname: string;
    exception: ptr JSValueRef): bool =
  if v.isNone:
    return true
  let d = v.get()
  let dobj = newObject(ctx)
  if not setPropChecked(ctx, dobj, "value",
      toJS(ctx, formatIcalDateTime(d.dt)), fname, exception):
    return false
  if not optSetStr(ctx, dobj, "tzid", d.tzid, fname, exception):
    return false
  setPropChecked(ctx, obj, key, dobj, fname, exception)

proc dtToJS(ctx: JSContextRef; d: IcalDt; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "value",
      toJS(ctx, formatIcalDateTime(d.dt)), fname, exception):
    return nil
  if not optSetStr(ctx, obj, "tzid", d.tzid, fname, exception):
    return nil
  obj

proc paramsToJS(ctx: JSContextRef; params: seq[IcalParam]; fname: string;
    exception: ptr JSValueRef): JSValueRef =
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

proc personToJS(ctx: JSContextRef; p: IcalPerson; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "uri", toJS(ctx, p.uri), fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "cn", p.cn, fname, exception):
    return nil
  if p.params.len > 0:
    let prm = paramsToJS(ctx, p.params, fname, exception)
    if prm == nil:
      return nil
    if not setPropChecked(ctx, obj, "params", prm, fname, exception):
      return nil
  obj

proc optSetPerson(ctx: JSContextRef; obj: JSObjectRef; key: string;
    v: Option[IcalPerson]; fname: string;
    exception: ptr JSValueRef): bool =
  if v.isNone:
    return true
  let p = personToJS(ctx, v.get(), fname, exception)
  if p == nil:
    return false
  setPropChecked(ctx, obj, key, p, fname, exception)

proc formatDur(d: IcalDuration): string =
  result = if d.negative: "-P" else: "P"
  if d.weeks != 0:
    result &= $d.weeks & "W"
  if d.days != 0:
    result &= $d.days & "D"
  var t = ""
  if d.hours != 0:
    t &= $d.hours & "H"
  if d.minutes != 0:
    t &= $d.minutes & "M"
  if d.seconds != 0:
    t &= $d.seconds & "S"
  if t.len > 0:
    result &= "T" & t
  if result == "P" or result == "-P":
    result &= "T0S"

proc triggerToJS(ctx: JSContextRef; t: IcalTrigger; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  case t.kind
  of trkRelative:
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "kind", toJS(ctx, "relative"),
        fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "duration",
        toJS(ctx, formatDur(t.dur)), fname, exception):
      return nil
    obj
  of trkAbsolute:
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "kind", toJS(ctx, "absolute"),
        fname, exception):
      return nil
    if not setPropChecked(ctx, obj, "dateTime",
        toJS(ctx, formatIcalDateTime(t.dt)), fname, exception):
      return nil
    obj

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

proc strsToJS(ctx: JSContextRef; strs: seq[string]): JSValueRef =
  var vals: seq[JSValueRef] = @[]
  for s in strs:
    vals.add(toJS(ctx, s))
  makeJSArray(ctx, vals)

proc alarmToJS(ctx: JSContextRef; a: IcalAlarm; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "action", toJS(ctx, a.action), fname,
      exception):
    return nil
  if a.trigger.isSome:
    let t = triggerToJS(ctx, a.trigger.get(), fname, exception)
    if t == nil:
      return nil
    if not setPropChecked(ctx, obj, "trigger", t, fname, exception):
      return nil
  if not optSetStr(ctx, obj, "description", a.description, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "summary", a.summary, fname, exception):
    return nil
  if a.repeatCount.isSome:
    if not setPropChecked(ctx, obj, "repeat",
        toJS(ctx, a.repeatCount.get()), fname, exception):
      return nil
  if a.duration.isSome:
    if not setPropChecked(ctx, obj, "duration",
        toJS(ctx, formatDur(a.duration.get())), fname, exception):
      return nil
  let attendees = seqToJS(ctx, a.attendees, fname, exception, personToJS)
  if attendees == nil:
    return nil
  if not setPropChecked(ctx, obj, "attendees", attendees, fname,
      exception):
    return nil
  obj

proc propToJS(ctx: JSContextRef; p: IcalProp; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "name", toJS(ctx, p.name), fname,
      exception):
    return nil
  let prm = paramsToJS(ctx, p.params, fname, exception)
  if prm == nil:
    return nil
  if not setPropChecked(ctx, obj, "params", prm, fname, exception):
    return nil
  if not setPropChecked(ctx, obj, "value", toJS(ctx, p.value), fname,
      exception):
    return nil
  obj

proc dtsToJS(ctx: JSContextRef; dts: seq[IcalDt]; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  seqToJS(ctx, dts, fname, exception,
    proc(ctx: JSContextRef; d: IcalDt; fname: string;
      exception: ptr JSValueRef): JSValueRef =
      dtToJS(ctx, d, fname, exception))

proc alarmsToJS(ctx: JSContextRef; alarms: seq[IcalAlarm]; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  seqToJS(ctx, alarms, fname, exception, alarmToJS)

proc propsToJS(ctx: JSContextRef; props: seq[IcalProp]; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  seqToJS(ctx, props, fname, exception, propToJS)

proc setSeqField(ctx: JSContextRef; obj: JSObjectRef; key: string;
    arr: JSValueRef; fname: string;
    exception: ptr JSValueRef): bool =
  ## Always-present sequence field (documented shape).
  if arr == nil:
    throwError(ctx, fname & ": could not convert result to JS",
      exception)
    return false
  setPropChecked(ctx, obj, key, arr, fname, exception)

proc eventToJS(ctx: JSContextRef; e: IcalEvent; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "uid", toJS(ctx, e.uid), fname,
      exception):
    return nil
  if not optSetDt(ctx, obj, "dtstamp", e.dtstamp, fname, exception):
    return nil
  if not optSetDt(ctx, obj, "dtstart", e.dtStart, fname, exception):
    return nil
  if not optSetDt(ctx, obj, "dtend", e.dtEnd, fname, exception):
    return nil
  if e.duration.isSome:
    if not setPropChecked(ctx, obj, "duration",
        toJS(ctx, formatDur(e.duration.get())), fname, exception):
      return nil
  if not optSetStr(ctx, obj, "summary", e.summary, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "description", e.description, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "location", e.location, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "status", e.status, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "transparency", e.transparency, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "classification", e.classification,
      fname, exception):
    return nil
  if e.priority.isSome:
    if not setPropChecked(ctx, obj, "priority",
        toJS(ctx, e.priority.get()), fname, exception):
      return nil
  if e.sequenceNum.isSome:
    if not setPropChecked(ctx, obj, "sequence",
        toJS(ctx, e.sequenceNum.get()), fname, exception):
      return nil
  if not optSetDt(ctx, obj, "created", e.created, fname, exception):
    return nil
  if not optSetDt(ctx, obj, "lastModified", e.lastModified, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "url", e.url, fname, exception):
    return nil
  if not optSetPerson(ctx, obj, "organizer", e.organizer, fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "attendees",
      seqToJS(ctx, e.attendees, fname, exception, personToJS), fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "categories", strsToJS(ctx, e.categories),
      fname, exception):
    return nil
  if not optSetStr(ctx, obj, "rrule", e.rrule, fname, exception):
    return nil
  if not setSeqField(ctx, obj, "exdates",
      dtsToJS(ctx, e.exdates, fname, exception), fname, exception):
    return nil
  if not setSeqField(ctx, obj, "attachments",
      strsToJS(ctx, e.attachments), fname, exception):
    return nil
  if not optSetDt(ctx, obj, "recurrenceId", e.recurrenceId, fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "alarms",
      alarmsToJS(ctx, e.alarms, fname, exception), fname, exception):
    return nil
  if e.extraProps.len > 0:
    if not setSeqField(ctx, obj, "extraProps",
        propsToJS(ctx, e.extraProps, fname, exception), fname, exception):
      return nil
  obj

proc todoToJS(ctx: JSContextRef; t: IcalTodo; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "uid", toJS(ctx, t.uid), fname,
      exception):
    return nil
  if not optSetDt(ctx, obj, "dtstamp", t.dtstamp, fname, exception):
    return nil
  if not optSetDt(ctx, obj, "dtstart", t.dtStart, fname, exception):
    return nil
  if not optSetDt(ctx, obj, "due", t.due, fname, exception):
    return nil
  if not optSetDt(ctx, obj, "completed", t.completed, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "summary", t.summary, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "description", t.description, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "location", t.location, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "status", t.status, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "classification", t.classification,
      fname, exception):
    return nil
  if t.priority.isSome:
    if not setPropChecked(ctx, obj, "priority",
        toJS(ctx, t.priority.get()), fname, exception):
      return nil
  if t.sequenceNum.isSome:
    if not setPropChecked(ctx, obj, "sequence",
        toJS(ctx, t.sequenceNum.get()), fname, exception):
      return nil
  if not optSetDt(ctx, obj, "created", t.created, fname, exception):
    return nil
  if not optSetDt(ctx, obj, "lastModified", t.lastModified, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "url", t.url, fname, exception):
    return nil
  if not optSetPerson(ctx, obj, "organizer", t.organizer, fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "attendees",
      seqToJS(ctx, t.attendees, fname, exception, personToJS), fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "categories", strsToJS(ctx, t.categories),
      fname, exception):
    return nil
  if not optSetStr(ctx, obj, "rrule", t.rrule, fname, exception):
    return nil
  if t.percentComplete.isSome:
    if not setPropChecked(ctx, obj, "percentComplete",
        toJS(ctx, t.percentComplete.get()), fname, exception):
      return nil
  if not setSeqField(ctx, obj, "alarms",
      alarmsToJS(ctx, t.alarms, fname, exception), fname, exception):
    return nil
  if t.extraProps.len > 0:
    if not setSeqField(ctx, obj, "extraProps",
        propsToJS(ctx, t.extraProps, fname, exception), fname, exception):
      return nil
  obj

proc journalToJS(ctx: JSContextRef; j: IcalJournal; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "uid", toJS(ctx, j.uid), fname,
      exception):
    return nil
  if not optSetDt(ctx, obj, "dtstamp", j.dtstamp, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "summary", j.summary, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "description", j.description, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "status", j.status, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "classification", j.classification,
      fname, exception):
    return nil
  if not optSetPerson(ctx, obj, "organizer", j.organizer, fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "categories", strsToJS(ctx, j.categories),
      fname, exception):
    return nil
  if not setSeqField(ctx, obj, "attendees",
      seqToJS(ctx, j.attendees, fname, exception, personToJS), fname,
      exception):
    return nil
  if j.extraProps.len > 0:
    if not setSeqField(ctx, obj, "extraProps",
        propsToJS(ctx, j.extraProps, fname, exception), fname, exception):
      return nil
  obj

proc tzObsToJS(ctx: JSContextRef; o: IcalTzObservance; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if o.dtstart.isSome:
    if not setPropChecked(ctx, obj, "dtstart",
        toJS(ctx, formatIcalDateTime(o.dtstart.get())), fname, exception):
      return nil
  if not optSetStr(ctx, obj, "offsetFrom", o.offsetFrom, fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "offsetTo", o.offsetTo, fname, exception):
    return nil
  if not setSeqField(ctx, obj, "names", strsToJS(ctx, o.names), fname,
      exception):
    return nil
  if not optSetStr(ctx, obj, "rrule", o.rrule, fname, exception):
    return nil
  if o.extraProps.len > 0:
    if not setSeqField(ctx, obj, "extraProps",
        propsToJS(ctx, o.extraProps, fname, exception), fname, exception):
      return nil
  obj

proc tzToJS(ctx: JSContextRef; t: IcalTimezone; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "tzid", toJS(ctx, t.tzid), fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "standard",
      seqToJS(ctx, t.standard, fname, exception, tzObsToJS), fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "daylight",
      seqToJS(ctx, t.daylight, fname, exception, tzObsToJS), fname,
      exception):
    return nil
  if t.extraProps.len > 0:
    if not setSeqField(ctx, obj, "extraProps",
        propsToJS(ctx, t.extraProps, fname, exception), fname, exception):
      return nil
  obj

proc genericToJS(ctx: JSContextRef; g: IcalGenericSub; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "name", toJS(ctx, g.name), fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "props",
      propsToJS(ctx, g.props, fname, exception), fname, exception):
    return nil
  if not setSeqField(ctx, obj, "children",
      seqToJS(ctx, g.children, fname, exception, genericToJS), fname,
      exception):
    return nil
  obj

proc otherToJS(ctx: JSContextRef; o: IcalOther; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "name", toJS(ctx, o.name), fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "props",
      propsToJS(ctx, o.props, fname, exception), fname, exception):
    return nil
  if not setSeqField(ctx, obj, "children",
      seqToJS(ctx, o.children, fname, exception, genericToJS), fname,
      exception):
    return nil
  obj

proc calToJS(ctx: JSContextRef; cal: IcalCalendar; fname: string;
    exception: ptr JSValueRef): JSValueRef =
  let obj = newObject(ctx)
  if not optSetStr(ctx, obj, "prodid", cal.prodId, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "version", cal.version, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "calscale", cal.calscale, fname, exception):
    return nil
  if not optSetStr(ctx, obj, "method", cal.`method`, fname, exception):
    return nil
  if cal.extraProps.len > 0:
    if not setSeqField(ctx, obj, "extraProps",
        propsToJS(ctx, cal.extraProps, fname, exception), fname,
        exception):
      return nil
  var events, todos, journals, timezones, others: seq[JSValueRef] = @[]
  for c in cal.components:
    case c.kind
    of cckEvent:
      let j = eventToJS(ctx, c.event, fname, exception)
      if j == nil:
        return nil
      events.add(j)
    of cckTodo:
      let j = todoToJS(ctx, c.todo, fname, exception)
      if j == nil:
        return nil
      todos.add(j)
    of cckJournal:
      let j = journalToJS(ctx, c.journal, fname, exception)
      if j == nil:
        return nil
      journals.add(j)
    of cckTimezone:
      let j = tzToJS(ctx, c.timezone, fname, exception)
      if j == nil:
        return nil
      timezones.add(j)
    of cckOther:
      let j = otherToJS(ctx, c.other, fname, exception)
      if j == nil:
        return nil
      others.add(j)
  if not setSeqField(ctx, obj, "events", makeJSArray(ctx, events), fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "todos", makeJSArray(ctx, todos), fname,
      exception):
    return nil
  if not setSeqField(ctx, obj, "journals", makeJSArray(ctx, journals),
      fname, exception):
    return nil
  if not setSeqField(ctx, obj, "timezones", makeJSArray(ctx, timezones),
      fname, exception):
    return nil
  if not setSeqField(ctx, obj, "others", makeJSArray(ctx, others),
      fname, exception):
    return nil
  obj

# -- live JS -> typed model ------------------------------------------------

proc rawHas(ctx: JSContextRef; obj: JSValueRef; key: string): bool =
  ## Present and not undefined (JSON drops undefined keys, so the old
  ## readers never saw them either).
  let k = newJSString(key)
  defer: JSStringRelease(k)
  var ex: JSValueRef = nil
  let prop = JSObjectGetProperty(ctx, obj, k, addr ex)
  ex == nil and prop != nil and
    JSValueGetType(ctx, prop) != kJSTypeUndefined

proc rawGet(ctx: JSContextRef; obj: JSValueRef; key: string): JSValueRef =
  ## Raw required property. Raises on throwing getters (internal).
  let k = newJSString(key)
  defer: JSStringRelease(k)
  var ex: JSValueRef = nil
  let prop = JSObjectGetProperty(ctx, obj, k, addr ex)
  if ex != nil or prop == nil:
    raise icalErr("has an unreadable property \"" & key & "\"")
  prop

proc requireObj(ctx: JSContextRef; v: JSValueRef; what: string): JSValueRef =
  ## Plain-object check with the caller's shape message.
  if v == nil or JSValueGetType(ctx, v) != kJSTypeObject or
      JSValueIsArray(ctx, v) or JSObjectIsFunction(ctx, v):
    raise icalErr(what)
  v

proc readStr(ctx: JSContextRef; v: JSValueRef; what: string): string =
  if v == nil or JSValueGetType(ctx, v) != kJSTypeString:
    raise icalErr(what)
  var ex: JSValueRef = nil
  let s = JSValueToStringCopy(ctx, v, addr ex)
  if s == nil:
    raise icalErr(what)
  defer: JSStringRelease(s)
  $s

proc readOptStr(ctx: JSContextRef; obj: JSValueRef;
    key: string): Option[string] =
  if not rawHas(ctx, obj, key):
    return none(string)
  some(readStr(ctx, rawGet(ctx, obj, key),
    "\"" & key & "\" must be a string"))

proc readOptInt(ctx: JSContextRef; obj: JSValueRef;
    key: string): Option[int] =
  if not rawHas(ctx, obj, key):
    return none(int)
  let v = rawGet(ctx, obj, key)
  if JSValueGetType(ctx, v) != kJSTypeNumber:
    raise icalErr("\"" & key & "\" must be an integer")
  var ex: JSValueRef = nil
  let f = JSValueToNumber(ctx, v, addr ex)
  if ex != nil or f != trunc(f) or abs(f) >= 9223372036854775808.0:
    raise icalErr("\"" & key & "\" must be an integer")
  some(int(f))

proc rawLen(ctx: JSContextRef; v: JSValueRef; what: string): int =
  var ex: JSValueRef = nil
  let lenKey = newJSString("length")
  defer: JSStringRelease(lenKey)
  let lenV = JSObjectGetProperty(ctx, v, lenKey, addr ex)
  if ex != nil or lenV == nil:
    raise icalErr(what)
  var ex2: JSValueRef = nil
  let n = int(JSValueToNumber(ctx, lenV, addr ex2))
  if ex2 != nil or n < 0:
    raise icalErr(what)
  n

proc rawIndex(ctx: JSContextRef; v: JSValueRef; idx: int;
    what: string): JSValueRef =
  var eEx: JSValueRef = nil
  let item = JSObjectGetPropertyAtIndex(ctx, v, cuint(idx), addr eEx)
  if eEx != nil or item == nil:
    raise icalErr(what)
  item

proc requireArr(ctx: JSContextRef; v: JSValueRef; what: string): JSValueRef =
  if v == nil or JSValueGetType(ctx, v) != kJSTypeObject or
      not JSValueIsArray(ctx, v):
    raise icalErr(what)
  v

proc readStrs(ctx: JSContextRef; obj: JSValueRef;
    key: string): seq[string] =
  if not rawHas(ctx, obj, key):
    return @[]
  let v = requireArr(ctx, rawGet(ctx, obj, key),
    "\"" & key & "\" must be an array")
  let n = rawLen(ctx, v, "\"" & key & "\" must be an array")
  for idx in 0 ..< n:
    result.add(readStr(ctx, rawIndex(ctx, v, idx,
      "\"" & key & "\" must list strings"),
      "\"" & key & "\" must list strings"))

proc readParams(ctx: JSContextRef; v: JSValueRef): seq[IcalParam] =
  let arr = requireArr(ctx, v, "\"params\" must be an array")
  let n = rawLen(ctx, arr, "\"params\" must be an array")
  for idx in 0 ..< n:
    let item = requireObj(ctx, rawIndex(ctx, arr, idx,
      "params entries need {name, values}"),
      "params entries need {name, values}")
    if not rawHas(ctx, item, "name") or not rawHas(ctx, item, "values"):
      raise icalErr("params entries need {name, values}")
    let name = readStr(ctx, rawGet(ctx, item, "name"),
      "params entries need {name, values}")
    let vv = requireArr(ctx, rawGet(ctx, item, "values"),
      "\"values\" must be an array")
    let vn = rawLen(ctx, vv, "\"values\" must be an array")
    var values: seq[string] = @[]
    for j in 0 ..< vn:
      values.add(readStr(ctx, rawIndex(ctx, vv, j,
        "\"values\" must list strings"),
        "\"values\" must list strings"))
    result.add(IcalParam(name: name, values: values))

proc readOptParams(ctx: JSContextRef; obj: JSValueRef;
    key: string): seq[IcalParam] =
  if not rawHas(ctx, obj, key):
    return @[]
  readParams(ctx, rawGet(ctx, obj, key))

proc readDt(ctx: JSContextRef; v: JSValueRef; key: string): IcalDt =
  let o = requireObj(ctx, v, "\"" & key & "\" must be {value, tzid?}")
  if not rawHas(ctx, o, "value"):
    raise icalErr("\"" & key & "\" must be {value, tzid?}")
  try:
    var d = IcalDt(dt: parseIcalDateTime(readStr(ctx,
      rawGet(ctx, o, "value"), "\"" & key & "\" must be {value, tzid?}")))
    let tz = readOptStr(ctx, o, "tzid")
    if tz.isSome:
      d.tzid = tz
    d
  except CatchableError as e:
    raise icalErr("\"" & key & "\": " & e.msg)

proc readOptDt(ctx: JSContextRef; obj: JSValueRef;
    key: string): Option[IcalDt] =
  if not rawHas(ctx, obj, key):
    return none(IcalDt)
  some(readDt(ctx, rawGet(ctx, obj, key), key))

proc readPerson(ctx: JSContextRef; v: JSValueRef; key: string): IcalPerson =
  let o = requireObj(ctx, v, "\"" & key & "\" must be {uri, cn?, params?}")
  if not rawHas(ctx, o, "uri"):
    raise icalErr("\"" & key & "\" must be {uri, cn?, params?}")
  var p = IcalPerson(uri: readStr(ctx, rawGet(ctx, o, "uri"),
    "\"" & key & "\" must be {uri, cn?, params?}"))
  p.cn = readOptStr(ctx, o, "cn")
  if rawHas(ctx, o, "params"):
    p.params = readParams(ctx, rawGet(ctx, o, "params"))
  p

proc readOptPerson(ctx: JSContextRef; obj: JSValueRef;
    key: string): Option[IcalPerson] =
  if not rawHas(ctx, obj, key):
    return none(IcalPerson)
  some(readPerson(ctx, rawGet(ctx, obj, key), key))

proc readPersons(ctx: JSContextRef; obj: JSValueRef;
    key: string): seq[IcalPerson] =
  if not rawHas(ctx, obj, key):
    return @[]
  let v = requireArr(ctx, rawGet(ctx, obj, key),
    "\"" & key & "\" must be an array")
  let n = rawLen(ctx, v, "\"" & key & "\" must be an array")
  for idx in 0 ..< n:
    result.add(readPerson(ctx, rawIndex(ctx, v, idx,
      "\"" & key & "\" entries must be {uri, ...}"), key))

proc readDts(ctx: JSContextRef; obj: JSValueRef;
    key: string): seq[IcalDt] =
  if not rawHas(ctx, obj, key):
    return @[]
  let v = requireArr(ctx, rawGet(ctx, obj, key),
    "\"" & key & "\" must be an array")
  let n = rawLen(ctx, v, "\"" & key & "\" must be an array")
  for idx in 0 ..< n:
    result.add(readDt(ctx, rawIndex(ctx, v, idx,
      "\"" & key & "\" must be {value, tzid?}"), key))

proc readDur(ctx: JSContextRef; obj: JSValueRef;
    key: string): Option[IcalDuration] =
  let s = readOptStr(ctx, obj, key)
  if s.isNone:
    return none(IcalDuration)
  try:
    some(parseIcalDuration(s.get()))
  except CatchableError as e:
    raise icalErr("\"" & key & "\": " & e.msg)

proc readOptTrigger(ctx: JSContextRef; obj: JSValueRef;
    key: string): Option[IcalTrigger] =
  if not rawHas(ctx, obj, key):
    return none(IcalTrigger)
  let v = requireObj(ctx, rawGet(ctx, obj, key),
    "\"" & key & "\" must be {kind, ...}")
  if not rawHas(ctx, v, "kind"):
    raise icalErr("\"" & key & "\" must be {kind, ...}")
  let kind = readStr(ctx, rawGet(ctx, v, "kind"),
    "\"" & key & "\" must be {kind, ...}")
  if kind == "relative":
    if not rawHas(ctx, v, "duration"):
      raise icalErr("relative trigger needs \"duration\"")
    try:
      some(IcalTrigger(kind: trkRelative, dur: parseIcalDuration(
        readStr(ctx, rawGet(ctx, v, "duration"),
          "relative trigger needs \"duration\""))))
    except CatchableError as e:
      raise icalErr("\"" & key & "\": " & e.msg)
  elif kind == "absolute":
    if not rawHas(ctx, v, "dateTime"):
      raise icalErr("absolute trigger needs \"dateTime\"")
    try:
      some(IcalTrigger(kind: trkAbsolute, dt: parseIcalDateTime(
        readStr(ctx, rawGet(ctx, v, "dateTime"),
          "absolute trigger needs \"dateTime\""))))
    except CatchableError as e:
      raise icalErr("\"" & key & "\": " & e.msg)
  else:
    raise icalErr("\"" & key & "\": unknown trigger kind \"" & kind & "\"")

proc readProp(ctx: JSContextRef; v: JSValueRef): IcalProp =
  let o = requireObj(ctx, v, "props entries need {name, params?, value}")
  if not rawHas(ctx, o, "name") or not rawHas(ctx, o, "value"):
    raise icalErr("props entries need {name, params?, value}")
  var params: seq[IcalParam] = @[]
  if rawHas(ctx, o, "params"):
    params = readParams(ctx, rawGet(ctx, o, "params"))
  IcalProp(name: readStr(ctx, rawGet(ctx, o, "name"),
    "props entries need {name, params?, value}"), params: params,
    value: readStr(ctx, rawGet(ctx, o, "value"),
      "props entries need {name, params?, value}"))

proc readProps(ctx: JSContextRef; obj: JSValueRef;
    key: string): seq[IcalProp] =
  if not rawHas(ctx, obj, key):
    return @[]
  let v = requireArr(ctx, rawGet(ctx, obj, key),
    "\"" & key & "\" must be an array")
  let n = rawLen(ctx, v, "\"" & key & "\" must be an array")
  for idx in 0 ..< n:
    result.add(readProp(ctx, rawIndex(ctx, v, idx,
      "props entries need {name, params?, value}")))

proc readAlarms(ctx: JSContextRef; obj: JSValueRef;
    key: string): seq[IcalAlarm] =
  if not rawHas(ctx, obj, key):
    return @[]
  let v = requireArr(ctx, rawGet(ctx, obj, key),
    "\"" & key & "\" must be an array")
  let n = rawLen(ctx, v, "\"" & key & "\" must be an array")
  for idx in 0 ..< n:
    let item = requireObj(ctx, rawIndex(ctx, v, idx,
      "alarms entries need {action, ...}"),
      "alarms entries need {action, ...}")
    if not rawHas(ctx, item, "action"):
      raise icalErr("alarms entries need {action, ...}")
    var a = IcalAlarm(action: readStr(ctx, rawGet(ctx, item, "action"),
      "alarms entries need {action, ...}"))
    a.trigger = readOptTrigger(ctx, item, "trigger")
    a.description = readOptStr(ctx, item, "description")
    a.summary = readOptStr(ctx, item, "summary")
    a.repeatCount = readOptInt(ctx, item, "repeat")
    a.duration = readDur(ctx, item, "duration")
    a.attendees = readPersons(ctx, item, "attendees")
    result.add(a)

proc jsToEvent(ctx: JSContextRef; v: JSValueRef; depth: int): IcalEvent =
  if depth > maxDumpDepth:
    raise icalErr("event is too deeply nested or circular")
  let o = requireObj(ctx, v, "events entries must be objects")
  result = IcalEvent(uid: readOptStr(ctx, o, "uid").get(""))
  result.dtstamp = readOptDt(ctx, o, "dtstamp")
  result.dtStart = readOptDt(ctx, o, "dtstart")
  result.dtEnd = readOptDt(ctx, o, "dtend")
  result.duration = readDur(ctx, o, "duration")
  result.summary = readOptStr(ctx, o, "summary")
  result.description = readOptStr(ctx, o, "description")
  result.location = readOptStr(ctx, o, "location")
  result.status = readOptStr(ctx, o, "status")
  result.transparency = readOptStr(ctx, o, "transparency")
  result.classification = readOptStr(ctx, o, "classification")
  result.priority = readOptInt(ctx, o, "priority")
  result.sequenceNum = readOptInt(ctx, o, "sequence")
  result.created = readOptDt(ctx, o, "created")
  result.lastModified = readOptDt(ctx, o, "lastModified")
  result.url = readOptStr(ctx, o, "url")
  result.organizer = readOptPerson(ctx, o, "organizer")
  result.attendees = readPersons(ctx, o, "attendees")
  result.categories = readStrs(ctx, o, "categories")
  result.rrule = readOptStr(ctx, o, "rrule")
  result.exdates = readDts(ctx, o, "exdates")
  result.attachments = readStrs(ctx, o, "attachments")
  result.recurrenceId = readOptDt(ctx, o, "recurrenceId")
  result.alarms = readAlarms(ctx, o, "alarms")
  result.extraProps = readProps(ctx, o, "extraProps")

proc jsToTodo(ctx: JSContextRef; v: JSValueRef; depth: int): IcalTodo =
  if depth > maxDumpDepth:
    raise icalErr("todo is too deeply nested or circular")
  let o = requireObj(ctx, v, "todos entries must be objects")
  result = IcalTodo(uid: readOptStr(ctx, o, "uid").get(""))
  result.dtstamp = readOptDt(ctx, o, "dtstamp")
  result.dtStart = readOptDt(ctx, o, "dtstart")
  result.due = readOptDt(ctx, o, "due")
  result.completed = readOptDt(ctx, o, "completed")
  result.summary = readOptStr(ctx, o, "summary")
  result.description = readOptStr(ctx, o, "description")
  result.location = readOptStr(ctx, o, "location")
  result.status = readOptStr(ctx, o, "status")
  result.classification = readOptStr(ctx, o, "classification")
  result.priority = readOptInt(ctx, o, "priority")
  result.sequenceNum = readOptInt(ctx, o, "sequence")
  result.created = readOptDt(ctx, o, "created")
  result.lastModified = readOptDt(ctx, o, "lastModified")
  result.url = readOptStr(ctx, o, "url")
  result.organizer = readOptPerson(ctx, o, "organizer")
  result.attendees = readPersons(ctx, o, "attendees")
  result.categories = readStrs(ctx, o, "categories")
  result.rrule = readOptStr(ctx, o, "rrule")
  result.percentComplete = readOptInt(ctx, o, "percentComplete")
  result.alarms = readAlarms(ctx, o, "alarms")
  result.extraProps = readProps(ctx, o, "extraProps")

proc jsToJournal(ctx: JSContextRef; v: JSValueRef; depth: int): IcalJournal =
  if depth > maxDumpDepth:
    raise icalErr("journal is too deeply nested or circular")
  let o = requireObj(ctx, v, "journals entries must be objects")
  result = IcalJournal(uid: readOptStr(ctx, o, "uid").get(""))
  result.dtstamp = readOptDt(ctx, o, "dtstamp")
  result.summary = readOptStr(ctx, o, "summary")
  result.description = readOptStr(ctx, o, "description")
  result.status = readOptStr(ctx, o, "status")
  result.classification = readOptStr(ctx, o, "classification")
  result.organizer = readOptPerson(ctx, o, "organizer")
  result.categories = readStrs(ctx, o, "categories")
  result.attendees = readPersons(ctx, o, "attendees")
  result.extraProps = readProps(ctx, o, "extraProps")

proc jsToTzObs(ctx: JSContextRef; v: JSValueRef): IcalTzObservance =
  let o = requireObj(ctx, v, "timezone observances must be objects")
  result = IcalTzObservance()
  let ds = readOptStr(ctx, o, "dtstart")
  if ds.isSome:
    try:
      result.dtstart = some(parseIcalDateTime(ds.get()))
    except CatchableError as e:
      raise icalErr("\"dtstart\": " & e.msg)
  result.offsetFrom = readOptStr(ctx, o, "offsetFrom")
  result.offsetTo = readOptStr(ctx, o, "offsetTo")
  result.names = readStrs(ctx, o, "names")
  result.rrule = readOptStr(ctx, o, "rrule")
  result.extraProps = readProps(ctx, o, "extraProps")

proc jsToTz(ctx: JSContextRef; v: JSValueRef): IcalTimezone =
  let o = requireObj(ctx, v, "timezones entries need {tzid, ...}")
  if not rawHas(ctx, o, "tzid"):
    raise icalErr("timezones entries need {tzid, ...}")
  result = IcalTimezone(tzid: readStr(ctx, rawGet(ctx, o, "tzid"),
    "timezones entries need {tzid, ...}"))
  if rawHas(ctx, o, "standard"):
    let s = requireArr(ctx, rawGet(ctx, o, "standard"),
      "timezones entries need {tzid, ...}")
    let n = rawLen(ctx, s, "timezones entries need {tzid, ...}")
    for idx in 0 ..< n:
      result.standard.add(jsToTzObs(ctx, rawIndex(ctx, s, idx,
        "timezone observances must be objects")))
  if rawHas(ctx, o, "daylight"):
    let s = requireArr(ctx, rawGet(ctx, o, "daylight"),
      "timezones entries need {tzid, ...}")
    let n = rawLen(ctx, s, "timezones entries need {tzid, ...}")
    for idx in 0 ..< n:
      result.daylight.add(jsToTzObs(ctx, rawIndex(ctx, s, idx,
        "timezone observances must be objects")))
  result.extraProps = readProps(ctx, o, "extraProps")

proc jsToGeneric(ctx: JSContextRef; v: JSValueRef; depth: int): IcalGenericSub =
  if depth > maxDumpDepth:
    raise icalErr("component is too deeply nested or circular")
  let o = requireObj(ctx, v, "generic components need {name, ...}")
  if not rawHas(ctx, o, "name"):
    raise icalErr("generic components need {name, ...}")
  result = IcalGenericSub(name: readStr(ctx, rawGet(ctx, o, "name"),
    "generic components need {name, ...}"))
  result.props = readProps(ctx, o, "props")
  if rawHas(ctx, o, "children"):
    let c = requireArr(ctx, rawGet(ctx, o, "children"),
      "generic components need {name, ...}")
    let n = rawLen(ctx, c, "generic components need {name, ...}")
    for idx in 0 ..< n:
      result.children.add(jsToGeneric(ctx, rawIndex(ctx, c, idx,
        "generic components need {name, ...}"), depth + 1))

proc jsToOther(ctx: JSContextRef; v: JSValueRef; depth: int): IcalOther =
  if depth > maxDumpDepth:
    raise icalErr("component is too deeply nested or circular")
  let o = requireObj(ctx, v, "other components need {name, ...}")
  if not rawHas(ctx, o, "name"):
    raise icalErr("other components need {name, ...}")
  result = IcalOther(name: readStr(ctx, rawGet(ctx, o, "name"),
    "other components need {name, ...}"))
  result.props = readProps(ctx, o, "props")
  if rawHas(ctx, o, "children"):
    let c = requireArr(ctx, rawGet(ctx, o, "children"),
      "other components need {name, ...}")
    let n = rawLen(ctx, c, "other components need {name, ...}")
    for idx in 0 ..< n:
      result.children.add(jsToGeneric(ctx, rawIndex(ctx, c, idx,
        "other components need {name, ...}"), depth + 1))

proc jsToCal(ctx: JSContextRef; v: JSValueRef): IcalCalendar =
  let node = requireObj(ctx, v, "calendar must be an object")
  result = IcalCalendar()
  result.prodId = readOptStr(ctx, node, "prodid")
  result.version = readOptStr(ctx, node, "version")
  result.calscale = readOptStr(ctx, node, "calscale")
  result.`method` = readOptStr(ctx, node, "method")
  result.extraProps = readProps(ctx, node, "extraProps")
  if rawHas(ctx, node, "events"):
    let e = requireArr(ctx, rawGet(ctx, node, "events"),
      "calendar must be an object")
    let n = rawLen(ctx, e, "calendar must be an object")
    for idx in 0 ..< n:
      result.components.add(IcalComponent(kind: cckEvent,
        event: jsToEvent(ctx, rawIndex(ctx, e, idx,
          "events entries must be objects"), 0)))
  if rawHas(ctx, node, "todos"):
    let e = requireArr(ctx, rawGet(ctx, node, "todos"),
      "calendar must be an object")
    let n = rawLen(ctx, e, "calendar must be an object")
    for idx in 0 ..< n:
      result.components.add(IcalComponent(kind: cckTodo,
        todo: jsToTodo(ctx, rawIndex(ctx, e, idx,
          "todos entries must be objects"), 0)))
  if rawHas(ctx, node, "journals"):
    let e = requireArr(ctx, rawGet(ctx, node, "journals"),
      "calendar must be an object")
    let n = rawLen(ctx, e, "calendar must be an object")
    for idx in 0 ..< n:
      result.components.add(IcalComponent(kind: cckJournal,
        journal: jsToJournal(ctx, rawIndex(ctx, e, idx,
          "journals entries must be objects"), 0)))
  if rawHas(ctx, node, "timezones"):
    let e = requireArr(ctx, rawGet(ctx, node, "timezones"),
      "calendar must be an object")
    let n = rawLen(ctx, e, "calendar must be an object")
    for idx in 0 ..< n:
      result.components.add(IcalComponent(kind: cckTimezone,
        timezone: jsToTz(ctx, rawIndex(ctx, e, idx,
          "timezones entries need {tzid, ...}"))))
  if rawHas(ctx, node, "others"):
    let e = requireArr(ctx, rawGet(ctx, node, "others"),
      "calendar must be an object")
    let n = rawLen(ctx, e, "calendar must be an object")
    for idx in 0 ..< n:
      result.components.add(IcalComponent(kind: cckOther,
        other: jsToOther(ctx, rawIndex(ctx, e, idx,
          "other components need {name, ...}"), 0)))

# -- JS entry points ---------------------------------------------------

## Builds the std/ical namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## ical.parse(text) -> {events, todos, journals, timezones, others}
      try:
        let j = calToJS(ctx, parseIcal(text), "parse", exception)
        if j == nil:
          throwError(ctx, "parse: could not convert result to JS",
            exception)
          return nil
        j
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify(value: JSValueRef):
      ## ical.stringify(cal) -> string (a VCALENDAR document)
      try:
        toJS(ctx, toIcal(jsToCal(ctx, value)))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
