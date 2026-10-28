# Bridge Nim <> JS — plan (agreed 2026-10-28)

## Decisions
- JS surface: global `require("std/<name>")`, lazy install, zero startup cost.
- Pilots: `std/env`, `std/fs` (sync). No `std/json`/openparser use yet
  (openparser stays a declared-only dep).
- Timers are **globals** Node-style: `setTimeout`/`setInterval`/
  `clearTimeout`/`clearInterval` (numeric ids).
- Async via powpow (`Development/packages/powpow`, pure-Nim kqueue loop).

## Files
- `src/carne/bridge.nim` (new): marshalling + registration helpers.
  `valueToString`, `setProp` (moved from runtime.nim), `toJS` overloads
  (string/int64/float/bool), `strArg`/`numArg`/`checkArity`,
  `throwError` (Nim error -> JS `Error` via `JSObjectMakeError`),
  `makeFunction`, `newObject`. Rule: no Nim exception escapes
  a `{.cdecl.}` callback.
- `src/carne/modules.nim` (new): `Runtime` ref (ctx, argv, loop, pending
  refcount, exit flag/code, uncaught, require cache, timer table),
  threadvar `currentRt`, installer table, global `require` installer.
- `src/carne/std/env.nim` (new): `args()`, `getenv(k)` (undefined when
  missing), `cwd()`, `exit(code)`.
- `src/carne/std/fs.nim` (new, sync): `readFile`, `writeFile`, `exists`,
  `readDir` (names), `mkdir`, `remove`.
- `src/carne/std/timers.nim` (new): globals above. JS functions held with
  `JSValueProtect` until fire/cancel; rest-args passed through to the
  callback; timer exceptions recorded as uncaught (exit 1 after drain).
- `src/carne/runtime.nim`: `runCode` creates one powpow `Loop` + `Runtime`,
  installs console/process/require/timers, evals, then `loop.run()` iff
  `pending > 0`. `decPending` calls `loop.stop()` at zero so the loop
  never blocks forever. `process.exit` sets flag + stops. Uncaught timer
  errors raise `CarneError` after drain.
- `carne.nimble`: add `requires "powpow"`.
- `tests/test_require.nim`, `tests/test_env.nim`, `tests/test_fs.nim`,
  `tests/test_timers.nim`; `examples/timers.js`, `examples/env_fs.js`.

## Verification
- `clue test`, `clue build src/carne.nim --out:bin/carne`.
- Manual: timer order, interval+clear, exit-when-idle, uncaught timer
  error exit code, require unknown module error, rest-args passthrough,
  promise resolved from a timer (microtask drain risk — verify by test).

## Status: built (2026-10-28)
- 28 tests pass across test1/env/fs/require/timers.
- Manual verified: timer ordering, intervals, env/fs example, exit(7),
  promise-from-timer, uncaught timer error (exit 1), prior behavior intact.
