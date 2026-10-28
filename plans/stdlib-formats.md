# std format libs on openparser (built 2026-10-28, batch: all ten)

## Decisions (as built; deviations from plan noted)
- All modules funnel through `JsonNode`: `bridge.jsonToJS`
  (`$node` + `JSValueMakeFromJSONString`), `bridge.jsToJson`
  (`JSValueCreateJSONString` + openparser `fromJson`), `bridge.returnJson`,
  `bridge.stripNulls` (drops none-Options from typed-model output).
- `std/yaml`: `parse`/`stringify` via `parseYAMLNode` + local
  `YamlNode->JsonNode` (the `parseHook(JsonNode)` path only reads the
  first scalar; openparser's `toJsonNode` is private). Single-doc v1.
- `std/toml`: local `TomlNode <-> JsonNode`; datetimes surface as the
  source literal, stringify back as strings. Root must be an object,
  null rejected.
- `std/ical`: full roundtrip as specified (dates {value, tzid?},
  durations "P1DT2H", persons/alarms/triggers/props, timezones, generic
  other-components, extraProps preserved).
- `std/xml`: `{tag, attrs, children}` as specified; cdata folds to
  strings; comments/prologs/doctypes dropped; root must be an element.
- `std/csv`: temp-file bridge (openparser CSV stays MemFile-based,
  no upstream change). `{headers, delimiter, quote}` options.
- `std/dotenv`: `parse` with expansion via exported `expandValue`,
  `load` into process env.
- `std/plist`: `parse`/`stringify` (`parsePlist`/`toXmlPlist`).
- `std/bson`: opaque U+0100+b mapping, NOT Latin-1: JSC's C API is
  NUL-terminated, so any mapping containing 0x00 truncates. Self-
  consistent roundtrip; do not read as text.
- `std/vcard`: parse-only (openparser's generic `toJson` is broken for
  `VCardName`, so a hand converter was written; no builder yet).
- `std/feed`: `parseRss`/`parseAtom`, hand converters (RssFeed.language
  is private, breaking the generic macro). Parse-only.
- Excluded as planned: `nif`, `html`, `sql/css/regex/diff/fuzzy/qr/svg/
  colors/mime/uuid/nanoid/path/gettext/fbe`.

## Files
- `src/carne/bridge.nim`: + `jsonToJS`, `jsToJson`, `returnJson`,
  `stripNulls` (imports `pkg/openparser/json`).
- `src/carne/std/{yaml,toml,ical,dotenv,plist,bson,vcard,feed,csv,xml}.nim`
- `src/carne/modules.nim`: ten registry rows.
- `tests/test_{yaml,toml,ical,dotenv,plist,bson,vcard,feed,csv,xml}.nim`:
  40 tests total.

## Verification
- 17/17 suites pass (`clue test`); manual per-module checks green;
  `run`/timers/help regression intact.
