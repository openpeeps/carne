---
title: iCalendar
description: "iCalendar parsing and serialization."
keywords: ['carne', 'javascript', 'std', 'ical', 'calendar']
---

# iCalendar

iCalendar parsing and serialization

```js
const ical = require("std/ical");
const cal = ical.parse("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTART:20260101T100000Z\r\nSUMMARY:Hi\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
console.log(cal.events.length);
console.log(ical.stringify(cal)); // a VCALENDAR document
```

Shape: `{events, todos, journals, timezones, others}`. Absent options
stay absent; dates serialize as `{value, tzid?}`, durations as `"P1DT2H"`
strings. Unknown properties ride along in `extraProps` and survive
the roundtrip.


## ical.parse

`ical.parse(text) -> {events, todos, journals, timezones, others}`

```js
const ical = require("std/ical");
ical.parse("example");
```

## ical.stringify

`ical.stringify(cal) -> string (a VCALENDAR document)`

```js
const ical = require("std/ical");
ical.stringify("example");
```
