# NimValue optimizations (agreed 2026-10-30)

## Context
All typed arg reads flow through `fromJS` (`8eb117d`). Stringify sites
and the http handler-return path stay on the `jsToJson` engine funnel
(Date/`toJSON`/`NaN` semantics only the engine gets right — do not touch).

Measured baseline: arg conversion lives inside `eval` (~57µs empty /
~619µs require-all-22). No large-data path snapshots today. Keep
`NimValue`; do not revert (it fixed 3 segfaults).

## Step 1 — lazy single-field reader (active)
`fromJS` deep-enumerates every property even when the caller wants one
field (O(n) for O(1) need). Add to `bridge.nim`, next to `nimArg`:

- `objArg(ctx, args, i, name, exception, obj: var JSValueRef): bool` —
  borrows the arg as an object ref, no snapshot. Rejects arrays
  ("options bags are plain objects", same message as today).
- `getField(ctx, obj, key, err): NimValue` — converts one property.
  Missing (or explicit `undefined`) yields `nvkUndefined` with empty err,
  so readers treat absent and undefined alike (matches
  `JSON.stringify`-drops-undefined and JS destructuring defaults).
- `jsKindName(ctx, v): string` — `jsTypeName` equivalent for live refs
  (for `objArg` type-error messages).

Rewrite the five structured readers to `(ctx, obj)` + `getField`:
`diff` readOpts, `qr` ecLevelArg, `csv` opts, `crypto` AEAD envelope,
`http` parseOpts (+ fetch/get/post sites; headers sub-object still
snapshots whole — all its keys are consumed). `nil` obj means absent.

Tests: wide object + `{context: undefined}` + extra keys accepted;
existing per-module suites must stay green (29 suites).

## Step 2 — array length cap (deferred)
`fromJS` has a depth cap (64) but no breadth cap. Cap array snapshots
(e.g. 100k elements) with a clear error. No behavior change for sane
inputs. Do after Step 1.

## Step 3 — nothing else (explicit non-goal)
Primitive fast-paths (`IsString` before `GetType`) save nanoseconds
against a 10ms startup dominated by dyld/JSC. `OrderedTable` per object
is fine at option-bag sizes. Revisit only with a bench number in hand.

## Verification
- `clue test test_nimvalue` + affected modules, then full `clue test`.
- `clue build src/carne.nim --out:bin/carne`; live `examples/http.js` curl.
