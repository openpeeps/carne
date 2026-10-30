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

import std/[json, options]

import javascriptcore

import pkg/openparser/ical

import ../bridge

proc icalErr(msg: string): ref CatchableError =
  newException(CatchableError, msg)

# -- typed model -> JsonNode ---------------------------------------------

proc dtToJson(d: IcalDt): JsonNode =
  result = %*{"value": formatIcalDateTime(d.dt)}
  if d.tzid.isSome:
    result["tzid"] = %d.tzid.get()

proc paramsToJson(params: seq[IcalParam]): JsonNode =
  result = newJArray()
  for p in params:
    var values = newJArray()
    for v in p.values:
      values.add(%v)
    result.add(%*{"name": p.name, "values": values})

proc personToJson(p: IcalPerson): JsonNode =
  result = %*{"uri": p.uri}
  if p.cn.isSome:
    result["cn"] = %p.cn.get()
  if p.params.len > 0:
    result["params"] = paramsToJson(p.params)

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

proc triggerToJson(t: IcalTrigger): JsonNode =
  case t.kind
  of trkRelative:
    %*{"kind": "relative", "duration": formatDur(t.dur)}
  of trkAbsolute:
    %*{"kind": "absolute", "dateTime": formatIcalDateTime(t.dt)}

proc alarmToJson(a: IcalAlarm): JsonNode =
  result = %*{"action": a.action}
  if a.trigger.isSome:
    result["trigger"] = triggerToJson(a.trigger.get())
  if a.description.isSome:
    result["description"] = %a.description.get()
  if a.summary.isSome:
    result["summary"] = %a.summary.get()
  if a.repeatCount.isSome:
    result["repeat"] = %a.repeatCount.get()
  if a.duration.isSome:
    result["duration"] = %formatDur(a.duration.get())
  var attendees = newJArray()
  for p in a.attendees:
    attendees.add(personToJson(p))
  result["attendees"] = attendees

proc propToJson(p: IcalProp): JsonNode =
  %*{"name": p.name, "params": paramsToJson(p.params), "value": p.value}

proc personsToJson(persons: seq[IcalPerson]): JsonNode =
  result = newJArray()
  for p in persons:
    result.add(personToJson(p))

proc strsToJson(strs: seq[string]): JsonNode =
  result = newJArray()
  for s in strs:
    result.add(%s)

proc dtsToJson(dts: seq[IcalDt]): JsonNode =
  result = newJArray()
  for d in dts:
    result.add(dtToJson(d))

proc alarmsToJson(alarms: seq[IcalAlarm]): JsonNode =
  result = newJArray()
  for a in alarms:
    result.add(alarmToJson(a))

proc propsToJson(props: seq[IcalProp]): JsonNode =
  result = newJArray()
  for p in props:
    result.add(propToJson(p))

proc optStrToJson(obj: JsonNode; key: string; v: Option[string]) =
  if v.isSome:
    obj[key] = %v.get()

proc optIntToJson(obj: JsonNode; key: string; v: Option[int]) =
  if v.isSome:
    obj[key] = %v.get()

proc optDtToJson(obj: JsonNode; key: string; v: Option[IcalDt]) =
  if v.isSome:
    obj[key] = dtToJson(v.get())

proc optPersonToJson(obj: JsonNode; key: string; v: Option[IcalPerson]) =
  if v.isSome:
    obj[key] = personToJson(v.get())

proc eventToJson(e: IcalEvent): JsonNode =
  result = %*{"uid": e.uid}
  optDtToJson(result, "dtstamp", e.dtstamp)
  optDtToJson(result, "dtstart", e.dtStart)
  optDtToJson(result, "dtend", e.dtEnd)
  if e.duration.isSome:
    result["duration"] = %formatDur(e.duration.get())
  optStrToJson(result, "summary", e.summary)
  optStrToJson(result, "description", e.description)
  optStrToJson(result, "location", e.location)
  optStrToJson(result, "status", e.status)
  optStrToJson(result, "transparency", e.transparency)
  optStrToJson(result, "classification", e.classification)
  optIntToJson(result, "priority", e.priority)
  optIntToJson(result, "sequence", e.sequenceNum)
  optDtToJson(result, "created", e.created)
  optDtToJson(result, "lastModified", e.lastModified)
  optStrToJson(result, "url", e.url)
  optPersonToJson(result, "organizer", e.organizer)
  result["attendees"] = personsToJson(e.attendees)
  result["categories"] = strsToJson(e.categories)
  optStrToJson(result, "rrule", e.rrule)
  result["exdates"] = dtsToJson(e.exdates)
  result["attachments"] = strsToJson(e.attachments)
  optDtToJson(result, "recurrenceId", e.recurrenceId)
  result["alarms"] = alarmsToJson(e.alarms)
  if e.extraProps.len > 0:
    result["extraProps"] = propsToJson(e.extraProps)

proc todoToJson(t: IcalTodo): JsonNode =
  result = %*{"uid": t.uid}
  optDtToJson(result, "dtstamp", t.dtstamp)
  optDtToJson(result, "dtstart", t.dtStart)
  optDtToJson(result, "due", t.due)
  optDtToJson(result, "completed", t.completed)
  optStrToJson(result, "summary", t.summary)
  optStrToJson(result, "description", t.description)
  optStrToJson(result, "location", t.location)
  optStrToJson(result, "status", t.status)
  optStrToJson(result, "classification", t.classification)
  optIntToJson(result, "priority", t.priority)
  optIntToJson(result, "sequence", t.sequenceNum)
  optDtToJson(result, "created", t.created)
  optDtToJson(result, "lastModified", t.lastModified)
  optStrToJson(result, "url", t.url)
  optPersonToJson(result, "organizer", t.organizer)
  result["attendees"] = personsToJson(t.attendees)
  result["categories"] = strsToJson(t.categories)
  optStrToJson(result, "rrule", t.rrule)
  optIntToJson(result, "percentComplete", t.percentComplete)
  result["alarms"] = alarmsToJson(t.alarms)
  if t.extraProps.len > 0:
    result["extraProps"] = propsToJson(t.extraProps)

proc journalToJson(j: IcalJournal): JsonNode =
  result = %*{"uid": j.uid}
  optDtToJson(result, "dtstamp", j.dtstamp)
  optStrToJson(result, "summary", j.summary)
  optStrToJson(result, "description", j.description)
  optStrToJson(result, "status", j.status)
  optStrToJson(result, "classification", j.classification)
  optPersonToJson(result, "organizer", j.organizer)
  result["categories"] = strsToJson(j.categories)
  result["attendees"] = personsToJson(j.attendees)
  if j.extraProps.len > 0:
    result["extraProps"] = propsToJson(j.extraProps)

proc tzObsToJson(o: IcalTzObservance): JsonNode =
  result = newJObject()
  if o.dtstart.isSome:
    result["dtstart"] = %formatIcalDateTime(o.dtstart.get())
  optStrToJson(result, "offsetFrom", o.offsetFrom)
  optStrToJson(result, "offsetTo", o.offsetTo)
  result["names"] = strsToJson(o.names)
  optStrToJson(result, "rrule", o.rrule)
  if o.extraProps.len > 0:
    result["extraProps"] = propsToJson(o.extraProps)

proc tzToJson(t: IcalTimezone): JsonNode =
  var standard = newJArray()
  for o in t.standard:
    standard.add(tzObsToJson(o))
  var daylight = newJArray()
  for o in t.daylight:
    daylight.add(tzObsToJson(o))
  result = %*{"tzid": t.tzid, "standard": standard, "daylight": daylight}
  if t.extraProps.len > 0:
    result["extraProps"] = propsToJson(t.extraProps)

proc genericToJson(g: IcalGenericSub): JsonNode =
  var props = newJArray()
  for p in g.props:
    props.add(propToJson(p))
  var children = newJArray()
  for c in g.children:
    children.add(genericToJson(c))
  %*{"name": g.name, "props": props, "children": children}

proc otherToJson(o: IcalOther): JsonNode =
  var props = newJArray()
  for p in o.props:
    props.add(propToJson(p))
  var children = newJArray()
  for c in o.children:
    children.add(genericToJson(c))
  %*{"name": o.name, "props": props, "children": children}

proc calToJson(cal: IcalCalendar): JsonNode =
  result = newJObject()
  optStrToJson(result, "prodid", cal.prodId)
  optStrToJson(result, "version", cal.version)
  optStrToJson(result, "calscale", cal.calscale)
  optStrToJson(result, "method", cal.`method`)
  if cal.extraProps.len > 0:
    result["extraProps"] = propsToJson(cal.extraProps)
  var events = newJArray()
  var todos = newJArray()
  var journals = newJArray()
  var timezones = newJArray()
  var others = newJArray()
  for c in cal.components:
    case c.kind
    of cckEvent: events.add(eventToJson(c.event))
    of cckTodo: todos.add(todoToJson(c.todo))
    of cckJournal: journals.add(journalToJson(c.journal))
    of cckTimezone: timezones.add(tzToJson(c.timezone))
    of cckOther: others.add(otherToJson(c.other))
  result["events"] = events
  result["todos"] = todos
  result["journals"] = journals
  result["timezones"] = timezones
  result["others"] = others

# -- JsonNode -> typed model ---------------------------------------------

proc fieldStr(o: JsonNode; key: string): Option[string] =
  if o.hasKey(key):
    let v = o[key]
    if v.kind != JString:
      raise icalErr("\"" & key & "\" must be a string")
    some(v.getStr())
  else:
    none(string)

proc fieldInt(o: JsonNode; key: string): Option[int] =
  if o.hasKey(key):
    let v = o[key]
    if v.kind != JInt:
      raise icalErr("\"" & key & "\" must be an integer")
    some(v.getInt())
  else:
    none(int)

proc fieldDt(o: JsonNode; key: string): Option[IcalDt] =
  if not o.hasKey(key):
    return none(IcalDt)
  let v = o[key]
  if v.kind != JObject or not v.hasKey("value") or v["value"].kind != JString:
    raise icalErr("\"" & key & "\" must be {value, tzid?}")
  try:
    var d = IcalDt(dt: parseIcalDateTime(v["value"].getStr()))
    let tz = fieldStr(v, "tzid")
    if tz.isSome:
      d.tzid = tz
    some(d)
  except CatchableError as e:
    raise icalErr("\"" & key & "\": " & e.msg)

proc fieldStrs(o: JsonNode; key: string): seq[string] =
  if not o.hasKey(key):
    return @[]
  let v = o[key]
  if v.kind != JArray:
    raise icalErr("\"" & key & "\" must be an array")
  for item in v:
    if item.kind != JString:
      raise icalErr("\"" & key & "\" must list strings")
    result.add(item.getStr())

proc fieldParams(v: JsonNode): seq[IcalParam] =
  if v.kind != JArray:
    raise icalErr("\"params\" must be an array")
  for item in v:
    if item.kind != JObject or not item.hasKey("name") or
        not item.hasKey("values"):
      raise icalErr("params entries need {name, values}")
    var values: seq[string] = @[]
    if item["values"].kind != JArray:
      raise icalErr("\"values\" must be an array")
    for s in item["values"]:
      if s.kind != JString:
        raise icalErr("\"values\" must list strings")
      values.add(s.getStr())
    result.add(IcalParam(name: item["name"].getStr(), values: values))

proc fieldPerson(o: JsonNode; key: string): Option[IcalPerson] =
  if not o.hasKey(key):
    return none(IcalPerson)
  let v = o[key]
  if v.kind != JObject or not v.hasKey("uri"):
    raise icalErr("\"" & key & "\" must be {uri, cn?, params?}")
  var p = IcalPerson(uri: v["uri"].getStr())
  p.cn = fieldStr(v, "cn")
  if v.hasKey("params"):
    p.params = fieldParams(v["params"])
  some(p)

proc fieldPersons(o: JsonNode; key: string): seq[IcalPerson] =
  if not o.hasKey(key):
    return @[]
  let v = o[key]
  if v.kind != JArray:
    raise icalErr("\"" & key & "\" must be an array")
  for item in v:
    if item.kind != JObject or not item.hasKey("uri"):
      raise icalErr("\"" & key & "\" entries must be {uri, ...}")
    var p = IcalPerson(uri: item["uri"].getStr())
    p.cn = fieldStr(item, "cn")
    if item.hasKey("params"):
      p.params = fieldParams(item["params"])
    result.add(p)

proc fieldDts(o: JsonNode; key: string): seq[IcalDt] =
  if not o.hasKey(key):
    return @[]
  let v = o[key]
  if v.kind != JArray:
    raise icalErr("\"" & key & "\" must be an array")
  for item in v:
    var wrap = newJObject()
    wrap["d"] = item
    let got = fieldDt(wrap, "d")
    if got.isSome:
      result.add(got.get())

proc fieldDur(o: JsonNode; key: string): Option[IcalDuration] =
  let s = fieldStr(o, key)
  if s.isNone:
    return none(IcalDuration)
  try:
    some(parseIcalDuration(s.get()))
  except CatchableError as e:
    raise icalErr("\"" & key & "\": " & e.msg)

proc fieldTrigger(o: JsonNode; key: string): Option[IcalTrigger] =
  if not o.hasKey(key):
    return none(IcalTrigger)
  let v = o[key]
  if v.kind != JObject or not v.hasKey("kind"):
    raise icalErr("\"" & key & "\" must be {kind, ...}")
  let kind = v["kind"].getStr()
  if kind == "relative":
    if not v.hasKey("duration"):
      raise icalErr("relative trigger needs \"duration\"")
    try:
      some(IcalTrigger(kind: trkRelative,
        dur: parseIcalDuration(v["duration"].getStr())))
    except CatchableError as e:
      raise icalErr("\"" & key & "\": " & e.msg)
  elif kind == "absolute":
    if not v.hasKey("dateTime"):
      raise icalErr("absolute trigger needs \"dateTime\"")
    try:
      some(IcalTrigger(kind: trkAbsolute,
        dt: parseIcalDateTime(v["dateTime"].getStr())))
    except CatchableError as e:
      raise icalErr("\"" & key & "\": " & e.msg)
  else:
    raise icalErr("\"" & key & "\": unknown trigger kind \"" & kind & "\"")

proc fieldProp(v: JsonNode): IcalProp =
  if v.kind != JObject or not v.hasKey("name") or not v.hasKey("value"):
    raise icalErr("props entries need {name, params?, value}")
  var params: seq[IcalParam] = @[]
  if v.hasKey("params"):
    params = fieldParams(v["params"])
  IcalProp(name: v["name"].getStr(), params: params,
    value: v["value"].getStr())

proc fieldProps(o: JsonNode; key: string): seq[IcalProp] =
  if not o.hasKey(key):
    return @[]
  let v = o[key]
  if v.kind != JArray:
    raise icalErr("\"" & key & "\" must be an array")
  for item in v:
    result.add(fieldProp(item))

proc fieldAlarms(o: JsonNode; key: string): seq[IcalAlarm] =
  if not o.hasKey(key):
    return @[]
  let v = o[key]
  if v.kind != JArray:
    raise icalErr("\"" & key & "\" must be an array")
  for item in v:
    if item.kind != JObject or not item.hasKey("action"):
      raise icalErr("alarms entries need {action, ...}")
    var a = IcalAlarm(action: item["action"].getStr())
    a.trigger = fieldTrigger(item, "trigger")
    a.description = fieldStr(item, "description")
    a.summary = fieldStr(item, "summary")
    a.repeatCount = fieldInt(item, "repeat")
    a.duration = fieldDur(item, "duration")
    a.attendees = fieldPersons(item, "attendees")
    result.add(a)

proc jsonToEvent(v: JsonNode): IcalEvent =
  if v.kind != JObject:
    raise icalErr("events entries must be objects")
  result = IcalEvent(uid: fieldStr(v, "uid").get(""))
  result.dtstamp = fieldDt(v, "dtstamp")
  result.dtStart = fieldDt(v, "dtstart")
  result.dtEnd = fieldDt(v, "dtend")
  result.duration = fieldDur(v, "duration")
  result.summary = fieldStr(v, "summary")
  result.description = fieldStr(v, "description")
  result.location = fieldStr(v, "location")
  result.status = fieldStr(v, "status")
  result.transparency = fieldStr(v, "transparency")
  result.classification = fieldStr(v, "classification")
  result.priority = fieldInt(v, "priority")
  result.sequenceNum = fieldInt(v, "sequence")
  result.created = fieldDt(v, "created")
  result.lastModified = fieldDt(v, "lastModified")
  result.url = fieldStr(v, "url")
  result.organizer = fieldPerson(v, "organizer")
  result.attendees = fieldPersons(v, "attendees")
  result.categories = fieldStrs(v, "categories")
  result.rrule = fieldStr(v, "rrule")
  result.exdates = fieldDts(v, "exdates")
  result.attachments = fieldStrs(v, "attachments")
  result.recurrenceId = fieldDt(v, "recurrenceId")
  result.alarms = fieldAlarms(v, "alarms")
  result.extraProps = fieldProps(v, "extraProps")

proc jsonToTodo(v: JsonNode): IcalTodo =
  if v.kind != JObject:
    raise icalErr("todos entries must be objects")
  result = IcalTodo(uid: fieldStr(v, "uid").get(""))
  result.dtstamp = fieldDt(v, "dtstamp")
  result.dtStart = fieldDt(v, "dtstart")
  result.due = fieldDt(v, "due")
  result.completed = fieldDt(v, "completed")
  result.summary = fieldStr(v, "summary")
  result.description = fieldStr(v, "description")
  result.location = fieldStr(v, "location")
  result.status = fieldStr(v, "status")
  result.classification = fieldStr(v, "classification")
  result.priority = fieldInt(v, "priority")
  result.sequenceNum = fieldInt(v, "sequence")
  result.created = fieldDt(v, "created")
  result.lastModified = fieldDt(v, "lastModified")
  result.url = fieldStr(v, "url")
  result.organizer = fieldPerson(v, "organizer")
  result.attendees = fieldPersons(v, "attendees")
  result.categories = fieldStrs(v, "categories")
  result.rrule = fieldStr(v, "rrule")
  result.percentComplete = fieldInt(v, "percentComplete")
  result.alarms = fieldAlarms(v, "alarms")
  result.extraProps = fieldProps(v, "extraProps")

proc jsonToJournal(v: JsonNode): IcalJournal =
  if v.kind != JObject:
    raise icalErr("journals entries must be objects")
  result = IcalJournal(uid: fieldStr(v, "uid").get(""))
  result.dtstamp = fieldDt(v, "dtstamp")
  result.summary = fieldStr(v, "summary")
  result.description = fieldStr(v, "description")
  result.status = fieldStr(v, "status")
  result.classification = fieldStr(v, "classification")
  result.organizer = fieldPerson(v, "organizer")
  result.categories = fieldStrs(v, "categories")
  result.attendees = fieldPersons(v, "attendees")
  result.extraProps = fieldProps(v, "extraProps")

proc jsonToTzObs(v: JsonNode): IcalTzObservance =
  if v.kind != JObject:
    raise icalErr("timezone observances must be objects")
  result = IcalTzObservance()
  let ds = fieldStr(v, "dtstart")
  if ds.isSome:
    try:
      result.dtstart = some(parseIcalDateTime(ds.get()))
    except CatchableError as e:
      raise icalErr("\"dtstart\": " & e.msg)
  result.offsetFrom = fieldStr(v, "offsetFrom")
  result.offsetTo = fieldStr(v, "offsetTo")
  result.names = fieldStrs(v, "names")
  result.rrule = fieldStr(v, "rrule")
  result.extraProps = fieldProps(v, "extraProps")

proc jsonToTz(v: JsonNode): IcalTimezone =
  if v.kind != JObject or not v.hasKey("tzid"):
    raise icalErr("timezones entries need {tzid, ...}")
  result = IcalTimezone(tzid: v["tzid"].getStr())
  if v.hasKey("standard"):
    for item in v["standard"]:
      result.standard.add(jsonToTzObs(item))
  if v.hasKey("daylight"):
    for item in v["daylight"]:
      result.daylight.add(jsonToTzObs(item))
  result.extraProps = fieldProps(v, "extraProps")

proc jsonToGeneric(v: JsonNode): IcalGenericSub =
  if v.kind != JObject or not v.hasKey("name"):
    raise icalErr("generic components need {name, ...}")
  result = IcalGenericSub(name: v["name"].getStr())
  result.props = fieldProps(v, "props")
  if v.hasKey("children"):
    for item in v["children"]:
      result.children.add(jsonToGeneric(item))

proc jsonToOther(v: JsonNode): IcalOther =
  if v.kind != JObject or not v.hasKey("name"):
    raise icalErr("other components need {name, ...}")
  result = IcalOther(name: v["name"].getStr())
  result.props = fieldProps(v, "props")
  if v.hasKey("children"):
    for item in v["children"]:
      result.children.add(jsonToGeneric(item))

proc jsonToCal(node: JsonNode): IcalCalendar =
  if node.kind != JObject:
    raise icalErr("calendar must be an object")
  result = IcalCalendar()
  result.prodId = fieldStr(node, "prodid")
  result.version = fieldStr(node, "version")
  result.calscale = fieldStr(node, "calscale")
  result.`method` = fieldStr(node, "method")
  result.extraProps = fieldProps(node, "extraProps")
  if node.hasKey("events"):
    for item in node["events"]:
      result.components.add(IcalComponent(kind: cckEvent,
        event: jsonToEvent(item)))
  if node.hasKey("todos"):
    for item in node["todos"]:
      result.components.add(IcalComponent(kind: cckTodo,
        todo: jsonToTodo(item)))
  if node.hasKey("journals"):
    for item in node["journals"]:
      result.components.add(IcalComponent(kind: cckJournal,
        journal: jsonToJournal(item)))
  if node.hasKey("timezones"):
    for item in node["timezones"]:
      result.components.add(IcalComponent(kind: cckTimezone,
        timezone: jsonToTz(item)))
  if node.hasKey("others"):
    for item in node["others"]:
      result.components.add(IcalComponent(kind: cckOther,
        other: jsonToOther(item)))

# -- JS entry points ---------------------------------------------------

## Builds the std/ical namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse(text: string):
      ## ical.parse(text) -> {events, todos, journals, timezones, others}
      try:
        returnJson(ctx, calToJson(parseIcal(text)), "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn stringify(value: JSValueRef):
      ## ical.stringify(cal) -> string (a VCALENDAR document)
      var err = ""
      let node = jsToJson(ctx, value, err)
      if node == nil:
        throwError(ctx, "stringify: " & err, exception)
        return nil
      try:
        toJS(ctx, toIcal(jsonToCal(node)))
      except CatchableError as e:
        throwError(ctx, "stringify: " & e.msg, exception)
        nil
