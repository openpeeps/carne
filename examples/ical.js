const ical = require("std/ical");

const src = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "PRODID:-//carne//demo//EN",
  "BEGIN:VEVENT",
  "UID:standup-1",
  "DTSTAMP:20260101T000000Z",
  "DTSTART:20260102T100000Z",
  "DTEND:20260102T101500Z",
  "SUMMARY:Team standup",
  "LOCATION:Room 3",
  "END:VEVENT",
  "BEGIN:VTODO",
  "UID:todo-1",
  "DTSTAMP:20260101T000000Z",
  "DUE:20260105T170000Z",
  "SUMMARY:Write release notes",
  "END:VTODO",
  "END:VCALENDAR",
  ""
].join("\r\n");

const cal = ical.parse(src);
console.log("version: " + cal.version);
console.log("event: " + cal.events[0].summary +
  " @ " + cal.events[0].dtstart.value +
  " (" + cal.events[0].location + ")");
console.log("todo due: " + cal.todos[0].due.value +
  " - " + cal.todos[0].summary);

const back = ical.stringify(cal);
console.log("roundtrip events: " + ical.parse(back).events.length);
