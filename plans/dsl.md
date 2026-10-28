# std module DSL (built 2026-10-28)

## Shape
```nim
init proc(module: Module) =
  exportObject:
    module.property greeting = "hi"

    module.registerFn readFile:
      ## fs.readFile(path) -> string (throws on IOError)
      ...
```
- `Module` (`bridge.nim`): `{ctx, ns}`. `init` generates `install*`;
  `modules.nim` untouched. `exportObject` takes no name (the namespace
  itself); reserved pattern for a future `exportClass Name:`.
- Strict containment: members only inside `exportObject:`; anything else
  there is a compile error. Bare setup statements under `init` pass
  through with `module` substituted.
- `module.registerFn` defines (nested `cdecl`, proven legal) AND attaches.
  `ctx.registerFn` is define-only for sub-namespace wiring (first used by
  `std/sql`: callbacks defined as setup statements, attached with
  `setProp` to child objects created via `newObject`). Setup has no
  `setupEx` in scope, so wiring passes `nil` (plain-object sets cannot
  throw). Shared Nim helpers (`doParse`/`doValidate`) take an explicit
  `name` and build their own `usage` lines, since `##` collection only
  reaches calls inside the callback body itself. Timers stays fully
  manual: globals + `setupEx` + shared helper.
- `module.property` attaches data: `propToJS` overloads for
  string/int/int64/float/bool/JsonNode; anything else fails at the line.
- Leading `##` in a member body is collected and appended to that
  member's `throwError` messages and `checkArity` usage line
  (`checkArity` grew `usage: string = ""`). No doc = zero behavior change.
- Blank line + `##` usage above... no: `##` goes INSIDE the body as the
  first statement; blank line separates members.

## Macro findings (Nim 2.2.10)
- `quote` is hygienic here: injected bodies cannot see quote-introduced
  bindings. Procs are built manually with gensym substitution (dot
  selectors and named-arg keys skipped; nested routine defs untouched).
- Hand-built shapes must match the parser exactly (`dumpAstGen` is the
  reference): 7-child `nnkProcDef`, 3-child `nnkIdentDefs` (always with
  default, even empty), `ptr T` = `nnkPtrTy` (not bracket expr),
  `addr x` = `nnkCommand`, `nil` = `newNilLit()`.
- `newIdentDefs` takes a SINGLE name; multi-name params need explicit
  `nnkIdentDefs.newTree`.
- Only `##` survives parsing (`#` vanishes); consecutive `##` lines merge
  into one CommentStmt, markers stripped.
- `exportObject` guard template errors outside `init` (macros expand
  outside-in, so `init` consumes the raw node first).
- No closures over callback bindings: `substBody` copies nested routine
  defs (incl. `nnkLambda`) verbatim while declarations become gensyms,
  so a lambda naming `ctx`/`args`/etc. breaks. Alias bindings to plain
  locals first (`let c = ctx`) and capture those; never capture `args`
  (dangling post-call) — copy values out. `std/http` per-fetch settle
  closures work this way (top-level `startFetch` + nested closures over
  its own params/locals).
- Async std modules hold `inc rt.pending` per live unit (fetch, server)
  and settle via `JSObjectMakeDeferredPromise` + `JSObjectCallAsFunction`
  on resolve/reject; protect all three values until settle. `runCodeEx`
  unwraps one top-level completion thenable (attach, drain, read
  `promiseText` / raise `CarneError`); floating promises settle through
  normal microtask checkpoints, no extra plumbing.
- `{.gcsafe.}` server dispatch: `OnRequestCallback` cannot capture, so
  look the JS handler up in a module-global table keyed by
  `cast[pointer](res.server)` inside one `{.cast(gcsafe).}` block
  (single thread in practice). Per-run client pools live in a second
  table freed by `closeAllServers` from the runtime teardown.

## Gotcha: `init` vs powpow
- `powpow/loop` re-exports `init` (`Platform.init`), which beats the macro
  in overload resolution; symptom is the guard error firing inside `init`.
  `std/env` uses `from powpow/loop import stop` (documented in the file).
  Guard message hints at shadowing.

## Verification
- 18/18 suites pass; error output verified to carry usage lines, e.g.
  `readFile: cannot open: /no/such/file` + `fs.readFile(path) -> ...`.
- Only `test_manifest`/`test_require` assert message text (non-DSL).
