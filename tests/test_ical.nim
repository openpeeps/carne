import unittest

import carne

const sampleIcs =
  "\"BEGIN:VCALENDAR\\r\\nVERSION:2.0\\r\\nPRODID:-//x//x//EN\\r\\n" &
  "BEGIN:VEVENT\\r\\nUID:1\\r\\nDTSTAMP:20260101T000000Z\\r\\n" &
  "DTSTART:20260102T100000Z\\r\\nDTEND:20260102T110000Z\\r\\n" &
  "SUMMARY:Standup\\r\\nLOCATION:Room 3\\r\\nEND:VEVENT\\r\\n" &
  "END:VCALENDAR\\r\\n\""

test "ical parse event":
  check runCode(
    "require('std/ical').parse(" & sampleIcs & ").events[0].summary") ==
    "Standup"
  check runCode(
    "require('std/ical').parse(" & sampleIcs & ").events[0].dtstart.value") ==
    "20260102T100000Z"
  check runCode(
    "require('std/ical').parse(" & sampleIcs & ").version") == "2.0"

test "ical absent options stay absent":
  check runCode(
    "'url' in require('std/ical').parse(" & sampleIcs & ").events[0]") ==
    "false"

test "ical stringify roundtrip":
  check runCode(
    "JSON.stringify(require('std/ical').parse(require('std/ical').stringify(" &
    "require('std/ical').parse(" & sampleIcs & "))).events[0])") ==
    runCode("JSON.stringify(require('std/ical').parse(" & sampleIcs &
      ").events[0])")

test "ical parse error throws":
  expect CarneError:
    discard runCode("require('std/ical').parse('not a calendar')")

test "ical stringify validates shapes":
  expect CarneError:
    discard runCode("require('std/ical').stringify({events: [42]})")
