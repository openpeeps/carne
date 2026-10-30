# std module DSL (built 2026-10-28, typed params 2026-10-30)

## Shape
```nim
init proc(module: Module) =
  exportObject:
    module.property greeting = "hi"

    module.registerFn readFile(path: string):
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
  throw). Shared Nim helpers (`doParse`/`doValidate`) now take extracted
  values + `docBlock` (the rendered JSDoc, in scope in every body) for
  their error paths. `registerFn(ctx, name(...)):` is the top-level form
  (used by `std/ws` handle methods, `std/timers`, runtime `console.log`);
  `ctx.registerFn` needs a declared `ctx`, which only exists inside
  `init`-generated code.
- `module.property` attaches data: `propToJS` overloads for
  string/int/int64/float/bool/JsonNode; anything else fails at the line.
- Leading `##` in a member body is collected and rendered as a JSDoc
  block (`jsDocBlock`): the block prefixes generated type mismatches and
  is appended to arity and `throwError` messages (bool helpers that throw
  from outside the body take `docBlock` explicitly). No doc = bare
  messages, zero behavior change.
- Blank line + `##` usage above... no: `##` goes INSIDE the body as the
  first statement; blank line separates members.

## Typed params (2026-10-30)
- Every header declares types; a bare name is a build error pointing at
  the form (`name()` for zero args). Arity (min from required, max from
  total) and one reader per param generate at compile time.
- Per-param forms: `name: Type` (required), `name ?: Type` (optional,
  zero default), `name: default(Type, value)` (optional, explicit
  default; used 3x: dotenv path, mix weight, conn close code).
- Type names map to `JsArgKind` (`bridge.nim`): `string`, `int`/`int64`
  (integral floats accepted), `float` (ints widen), `bool`, `NimValue`
  (snapshot of anything), `JSObjectRef` (checked live object, arrays
  rejected), `JSValueRef` (raw live ref: overload dispatch, JS-coercion
  and JSON-serialize passthroughs), `RestArgs` (variadic tail, last
  only, open max via `checkArityMin`). Unknown names are a build error.
- Rules enforced at compile time: required-after-optional, RestArgs
  last/once, reserved param names (`ctx function thisObject
  argumentCount arguments exception args docBlock`).
- Parser shapes: command-position headers parse as ObjConstr
  (colon-first) or Call (`?`-first/`()`); the normalizer accepts both,
  skipping Empty nodes. Multi-declare (`a, b: T`) is unsupported.
  `?:` needs spaces both sides (Spacing warning otherwise).
- Generated scope per body: the bindings plus `args` (pre-cast),
  `argumentCount`, `docBlock`. Overloaded middles (serve port/host)
  dispatch on `int(argumentCount)` with `throwTypeMismatch` + `docBlock`.
- Domain readers went value-form (`colors.colorVal`, `diff.readOpts`,
  `ws.readHandlers`, `gettext.openTemp` take `docBlock`, default `""`).
  Raising helpers need nothing (body catch + `addErrorContext`).
- Error format: type errors are block-first
  (`/*...*/\ntype mismatch parameter: \`p\`. Got \`a\`, expected \`w\``);
  arity/body errors keep message-first with the block appended.

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
- Typed params: 31/31 suites green; `test_nimvalue` locks the new
  format (JSDoc block first on mismatch, after on arity) and the
  `default()` weight passthrough via `colors.mix`.
