# Carne bridge: shared Nim <> JS marshalling and registration helpers.
#
# Every std module builds on these, so authoring a module stays small.
# Rule: no Nim exception may escape a {.cdecl.} JS callback; Nim errors
# become JS Error throws via throwError.

import std/macros
import std/tables

import pkg/openparser/json

import javascriptcore

import powpow/types
import powpow/loop

type
  TimerEntry* = object
    ## One live JS timer: the powpow id, the protected JS callback,
    ## protected passthrough args, and whether it repeats.
    id*: TimerId
    fn*: JSObjectRef
    rest*: seq[JSValueRef]
    isInterval*: bool

  Runtime* = ref object
    ## Per-run shared state: JS context, argv, powpow loop, pending-work
    ## refcount, exit signalling, require cache, live timers.
    ctx*: JSContextRef
    argv*: seq[string]
    loop*: Loop
    pending*: int
    exitRequested*: bool
    exitCode*: int
    uncaught*: string
    instances*: Table[string, JSObjectRef]
    timerSeq*: int
    timers*: Table[int, TimerEntry]
    promiseSettled*: bool
    promiseRejected*: bool
    promiseText*: string

var rtThread {.threadvar.}: Runtime

proc currentRt*(): Runtime =
  ## The run currently executing on this thread. Set by runCode.
  rtThread

proc setCurrentRt*(rt: Runtime) =
  rtThread = rt

proc ensureLoop*(rt: Runtime): Loop =
  ## Creates the run's powpow loop on first async need (timers, fetch,
  ## serve) and returns it. Pure-sync scripts never pay for kqueue +
  ## table preallocation. Every `inc rt.pending` site must go through
  ## here first, so pending > 0 implies a live loop.
  if rt.loop == nil:
    rt.loop = newLoop()
  rt.loop

type
  CarneError* = object of CatchableError

  Module* = ref object
    ## A std module under construction: the JS context plus the
    ## namespace object that `init` returns for `require("std/...")`.
    ctx*: JSContextRef
    ns*: JSObjectRef

proc valueToString*(ctx: JSContextRef; value: JSValueRef): string =
  ## Converts a JS value via String(value). Empty string on failure.
  var ex: JSValueRef = nil
  let s = JSValueToStringCopy(ctx, value, addr ex)
  if s == nil:
    return ""
  defer: JSStringRelease(s)
  $s

proc setProp*(ctx: JSContextRef; obj: JSObjectRef; name: string;
    value: JSValueRef; setupEx: ptr JSValueRef) =
  let key = newJSString(name)
  defer: JSStringRelease(key)
  JSObjectSetProperty(ctx, obj, key, value, kJSPropertyAttributeNone, setupEx)

proc newObject*(ctx: JSContextRef): JSObjectRef =
  JSObjectMake(ctx, nil, nil)

proc makeFunction*(ctx: JSContextRef; name: string;
    cb: JSObjectCallAsFunctionCallback): JSObjectRef =
  ## Wraps a Nim callback as a JS function.
  let jsName = newJSString(name)
  defer: JSStringRelease(jsName)
  JSObjectMakeFunctionWithCallback(ctx, jsName, cb)

proc toJS*(ctx: JSContextRef; s: string): JSValueRef =
  let jsStr = newJSString(s)
  defer: JSStringRelease(jsStr)
  JSValueMakeString(ctx, jsStr)

proc toJS*(ctx: JSContextRef; n: int64): JSValueRef =
  JSValueMakeNumber(ctx, cdouble(n))

proc toJS*(ctx: JSContextRef; n: int): JSValueRef =
  JSValueMakeNumber(ctx, cdouble(n))

proc toJS*(ctx: JSContextRef; f: float): JSValueRef =
  JSValueMakeNumber(ctx, cdouble(f))

proc toJS*(ctx: JSContextRef; b: bool): JSValueRef =
  JSValueMakeBoolean(ctx, b)

proc throwError*(ctx: JSContextRef; msg: string;
    exception: ptr JSValueRef) =
  ## Throws a JS Error with msg. Returns nil for convenience.
  if exception == nil:
    return
  var ex: JSValueRef = nil
  let text = toJS(ctx, msg)
  let err = JSObjectMakeError(ctx, 1, unsafeAddr text, addr ex)
  if err != nil:
    exception[] = err

proc checkArity*(argumentCount: csize_t; wantMin, wantMax: int;
    name: string; ctx: JSContextRef;
    exception: ptr JSValueRef; usage: string = ""): bool =
  ## Validates arg count, throwing a JS Error on mismatch. `usage` is
  ## appended to the message when provided (the `init` macro fills it
  ## from the member's `##` doc comment).
  let n = int(argumentCount)
  if n < wantMin or n > wantMax:
    var msg = name & ": expected "
    if wantMin == wantMax:
      msg &= $wantMin & " argument(s), got " & $n
    else:
      msg &= $wantMin & "-" & $wantMax & " argument(s), got " & $n
    if usage.len > 0:
      msg &= "\n" & usage
    throwError(ctx, msg, exception)
    return false
  true

proc strArg*(ctx: JSContextRef; args: ptr UncheckedArray[JSValueRef];
    i: int; name: string; exception: ptr JSValueRef;
    val: var string): bool =
  ## Reads arg i as a string. False + JS throw on failure.
  var ex: JSValueRef = nil
  let s = JSValueToStringCopy(ctx, args[i], addr ex)
  if s == nil:
    throwError(ctx, name & ": argument " & $i & " is not convertible to string",
      exception)
    return false
  val = $s
  JSStringRelease(s)
  true

proc numArg*(ctx: JSContextRef; args: ptr UncheckedArray[JSValueRef];
    i: int; name: string; exception: ptr JSValueRef;
    val: var float): bool =
  ## Reads arg i via Number(arg). False + JS throw on failure.
  var ex: JSValueRef = nil
  val = JSValueToNumber(ctx, args[i], addr ex)
  if ex != nil:
    throwError(ctx, name & ": argument " & $i & " is not a number", exception)
    return false
  true

proc jsonToJS*(ctx: JSContextRef; node: JsonNode): JSValueRef =
  ## Parses $node as JSON into a fresh JS value. nil on failure
  ## (only when $node is not valid JSON, e.g. NaN payloads).
  let s = $node
  let jsStr = newJSString(s)
  defer: JSStringRelease(jsStr)
  JSValueMakeFromJSONString(ctx, jsStr)

proc jsToJson*(ctx: JSContextRef; value: JSValueRef;
    err: var string): JsonNode =
  ## JSON.stringify(value), parsed with openparser. nil + err message
  ## on failure (circular structures, BigInt, undefined).
  var ex: JSValueRef = nil
  let jsStr = JSValueCreateJSONString(ctx, value, 0, addr ex)
  if jsStr == nil:
    err = "value is not JSON-serializable"
    return nil
  defer: JSStringRelease(jsStr)
  try:
    fromJson($jsStr)
  except CatchableError as e:
    err = e.msg
    nil

proc returnJson*(ctx: JSContextRef; node: JsonNode; name: string;
    exception: ptr JSValueRef): JSValueRef =
  ## jsonToJS with a JS throw on failure. nil on failure.
  let v = jsonToJS(ctx, node)
  if v == nil:
    throwError(ctx, name & ": could not convert result to JS", exception)
    return nil
  v

proc stripNulls*(node: JsonNode): JsonNode =
  ## Drops object fields whose value is JNull (options that were none).
  ## Array elements are kept as-is. Returns a fresh tree.
  case node.kind
  of JObject:
    result = newJObject()
    for k, v in node.pairs:
      if v.kind != JNull:
        result[k] = stripNulls(v)
  of JArray:
    result = newJArray()
    for item in node:
      result.add(stripNulls(item))
  else:
    result = node

proc propToJS*(ctx: JSContextRef; v: string): JSValueRef =
  ## `module.property` value conversion. Anything outside these
  ## overloads fails to compile at the `property` line.
  toJS(ctx, v)

proc propToJS*(ctx: JSContextRef; v: int): JSValueRef =
  toJS(ctx, v)

proc propToJS*(ctx: JSContextRef; v: int64): JSValueRef =
  toJS(ctx, v)

proc propToJS*(ctx: JSContextRef; v: float): JSValueRef =
  toJS(ctx, v)

proc propToJS*(ctx: JSContextRef; v: bool): JSValueRef =
  toJS(ctx, v)

proc propToJS*(ctx: JSContextRef; v: JsonNode): JSValueRef =
  let r = jsonToJS(ctx, v)
  if r == nil:
    jsonToJS(ctx, newJNull())
  else:
    r

template exportObject*(body: untyped): untyped =
  ## Marker for member declarations inside `init`. Only `init`
  ## understands it; direct expansion is a compile error.
  {.error: "exportObject is only valid directly inside an init block" &
    " (if you are inside one, `init` is shadowed by another import:" &
    " qualify it or narrow the import)".}

type
  FnBindings = object
    ctxName: string
    ctxSym, functionSym, thisObjectSym: NimNode
    argcSym, argvSym, exSym, argsSym: NimNode

proc newBindings(ctxName: string): FnBindings =
  FnBindings(ctxName: ctxName, ctxSym: genSym(nskParam, ctxName),
    functionSym: genSym(nskParam, "function"),
    thisObjectSym: genSym(nskParam, "thisObject"),
    argcSym: genSym(nskParam, "argumentCount"),
    argvSym: genSym(nskParam, "arguments"),
    exSym: genSym(nskParam, "exception"),
    argsSym: genSym(nskLet, "args"))

const routineKinds = {nnkProcDef, nnkFuncDef, nnkMethodDef, nnkMacroDef,
  nnkTemplateDef, nnkIteratorDef, nnkConverterDef, nnkLambda}

proc substBody(n: NimNode; b: FnBindings): NimNode =
  ## Rewrites callback-body identifiers to the generated proc's gensyms.
  ## Nested routine definitions are left untouched (they cannot see the
  ## bindings). Dot selectors and named-arg keys are never rewritten.
  if n.kind == nnkIdent:
    if n.strVal == b.ctxName:
      return b.ctxSym
    case n.strVal
    of "function": return b.functionSym
    of "thisObject": return b.thisObjectSym
    of "argumentCount": return b.argcSym
    of "arguments": return b.argvSym
    of "exception": return b.exSym
    of "args": return b.argsSym
    else: return copy(n)
  if n.kind in routineKinds:
    return copy(n)
  result = copyNimNode(n)
  for i, child in n.pairs:
    if (n.kind == nnkDotExpr and i == 1) or
        (n.kind in {nnkExprColonExpr, nnkExprEqExpr} and i == 0):
      result.add(copy(child))
    else:
      result.add(substBody(child, b))

proc substModule(n: NimNode; mname: string; moduleSym: NimNode): NimNode =
  ## Rewrites the `init` module name to the generated module symbol in
  ## setup statements and property values (which run in install scope).
  if n.kind == nnkIdent:
    if n.strVal == mname:
      return moduleSym
    return copy(n)
  result = copyNimNode(n)
  for i, child in n.pairs:
    if (n.kind == nnkDotExpr and i == 1) or
        (n.kind in {nnkExprColonExpr, nnkExprEqExpr} and i == 0):
      result.add(copy(child))
    else:
      result.add(substModule(child, mname, moduleSym))

proc addErrorContext(n: NimNode; doc: string): NimNode =
  ## Appends the member doc to every `throwError` message and passes it
  ## as `usage` to `checkArity` calls. Same traversal rules as substBody.
  if n.kind == nnkCall and n.len >= 4 and n[0].kind == nnkIdent and
      n[0].strVal == "throwError":
    result = copyNimNode(n)
    result.add(copy(n[0]))
    result.add(copy(n[1]))
    result.add(nnkInfix.newTree(newIdentNode("&"), copy(n[2]),
      newStrLitNode("\n" & doc)))
    for i in 3 ..< n.len:
      result.add(copy(n[i]))
    return
  if n.kind == nnkCall and n.len == 7 and n[0].kind == nnkIdent and
      n[0].strVal == "checkArity":
    result = copyNimNode(n)
    for child in n:
      result.add(copy(child))
    result.add(newStrLitNode(doc))
    return
  if n.kind in routineKinds:
    return copy(n)
  result = copyNimNode(n)
  for i, child in n.pairs:
    if (n.kind == nnkDotExpr and i == 1) or
        (n.kind in {nnkExprColonExpr, nnkExprEqExpr} and i == 0):
      result.add(copy(child))
    else:
      result.add(addErrorContext(child, doc))

proc buildCallbackFn*(fname: string; ctxName: string;
    fnBody: NimNode): NimNode =
  ## Builds the nested `cdecl` callback proc named `fname`. Leading
  ## `##` doc comments in the body are collected and appended to the
  ## proc's error messages (see addErrorContext):
  ##
  ##   module.registerFn readFile:
  ##     ## fs.readFile(path) -> string
  ##     ...
  let b = newBindings(ctxName)
  var doc = ""
  if fnBody.kind == nnkStmtList:
    for stmt in fnBody:
      if stmt.kind == nnkCommentStmt:
        doc =
          if doc.len > 0: doc & "\n" & stmt.strVal
          else: stmt.strVal
      else:
        break
  let body = newStmtList()
  body.add(newLetStmt(b.argsSym,
    nnkCast.newTree(
      nnkPtrTy.newTree(
        nnkBracketExpr.newTree(
          newIdentNode("UncheckedArray"), newIdentNode("JSValueRef"))),
      b.argvSym)))
  let subbed = substBody(fnBody, b)
  body.add(if doc.len > 0: addErrorContext(subbed, doc) else: subbed)

  let ptrJsVal = nnkPtrTy.newTree(newIdentNode("JSValueRef"))
  let formal = newNimNode(nnkFormalParams)
  formal.add(newIdentNode("JSValueRef"))
  formal.add(nnkIdentDefs.newTree(b.ctxSym, newIdentNode("JSContextRef"),
    newEmptyNode()))
  formal.add(nnkIdentDefs.newTree(b.functionSym, b.thisObjectSym,
    newIdentNode("JSObjectRef"), newEmptyNode()))
  formal.add(nnkIdentDefs.newTree(b.argcSym, newIdentNode("csize_t"),
    newEmptyNode()))
  formal.add(nnkIdentDefs.newTree(b.argvSym, ptrJsVal, newEmptyNode()))
  formal.add(nnkIdentDefs.newTree(b.exSym, ptrJsVal, newEmptyNode()))

  result = newNimNode(nnkProcDef)
  result.add(newIdentNode(fname))
  result.add(newEmptyNode())
  result.add(newEmptyNode())
  result.add(formal)
  result.add(newNimNode(nnkPragma).add(newIdentNode("cdecl")))
  result.add(newEmptyNode())
  result.add(body)

macro registerFn*(ctx: untyped; ident: untyped; fnBody: untyped): untyped =
  ## Defines a JSC callback named `ident` with the standard
  ## `JSObjectCallAsFunctionCallback` shape. The body runs with `ctx`
  ## (named after the passed context), `function`, `thisObject`,
  ## `argumentCount`, `arguments`, `exception` and a pre-cast `args`
  ## in scope:
  ##
  ##   ctx.registerFn readFile:
  ##     if not checkArity(argumentCount, 1, 1, "readFile", ctx, exception):
  ##       return nil
  ##
  ## Definition only; registration stays explicit, as before:
  ##
  ##   setProp(ctx, ns, "readFile",
  ##     makeFunction(ctx, "readFile", readFile), addr ex)
  ##
  ## Note: `quote` cannot express this (it is hygienic: injected bodies
  ## cannot see quote-introduced bindings), so the proc is built manually
  ## and body identifiers are substituted with gensyms. Nested routine
  ## definitions inside the body are left untouched.
  let ctxName = if ctx.kind == nnkIdent: ctx.strVal else: "ctx"
  result = buildCallbackFn($ident, ctxName, fnBody)

proc dotCallTarget(n: NimNode; mname, field: string): bool =
  ## True when `n` is `mname.field(...)` / `mname.field ...`.
  (n.kind in {nnkCommand, nnkCall}) and n.len > 0 and
    n[0].kind == nnkDotExpr and n[0][0].kind == nnkIdent and
    n[0][0].strVal == mname and n[0][1].kind == nnkIdent and
    n[0][1].strVal == field

macro init*(def: untyped): untyped =
  ## Module initializer. Takes `proc(<name>: Module) = ...` and
  ## generates the `install*` entry point behind `require("std/...")`:
  ##
  ##   init proc(module: Module) =
  ##     exportObject:
  ##       module.property greeting = "hi"
  ##       module.registerFn readFile:
  ##         ...
  ##
  ## `module.registerFn` defines the callback and attaches it to the
  ## namespace; `module.property` attaches a data value (string, int,
  ## float, bool, JsonNode). A `##` doc comment on a member is collected
  ## and appended to that member's error messages. Bare statements run
  ## as init-time setup code. Member declarations outside `exportObject:`
  ## are an error, as is anything but members inside it.
  if def.kind != nnkLambda:
    error("init expects `proc(<name>: Module) = ...`", def)
  var formal: NimNode = nil
  for child in def:
    if child.kind == nnkFormalParams:
      formal = child
      break
  if formal == nil or formal.len != 2 or formal[1].kind != nnkIdentDefs or
      formal[1].len != 3 or formal[1][0].kind != nnkIdent or
      formal[1][1].kind != nnkIdent or formal[1][1].strVal != "Module":
    error("init expects exactly one parameter of type Module", def)
  let mname = formal[1][0].strVal
  let body = def[^1]
  if body.kind != nnkStmtList:
    error("init expects a block body", def)

  let moduleSym = genSym(nskLet, "module")
  let exSym = genSym(nskVar, "ex")
  let ctxId = newIdentNode("ctx")
  let nsOf = nnkDotExpr.newTree(moduleSym, newIdentNode("ns"))

  let outStmts = newStmtList()
  for stmt in body:
    if stmt.kind in {nnkCommand, nnkCall} and stmt.len > 0 and
        stmt[0].kind == nnkIdent and stmt[0].strVal == "exportObject":
      if stmt.len != 2 or stmt[1].kind != nnkStmtList:
        error("exportObject takes a single block", stmt)
      for member in stmt[1]:
        if member.kind == nnkCommentStmt:
          continue
        elif dotCallTarget(member, mname, "registerFn"):
          if member.len != 3 or member[1].kind != nnkIdent or
              member[2].kind != nnkStmtList:
            error("registerFn expects a name and a body", member)
          let fname = member[1].strVal
          outStmts.add(buildCallbackFn(fname, "ctx", member[2]))
          outStmts.add(newCall("setProp", ctxId, copy(nsOf),
            newStrLitNode(fname),
            newCall("makeFunction", ctxId, newStrLitNode(fname),
              newIdentNode(fname)),
            nnkCommand.newTree(newIdentNode("addr"), exSym)))
        elif dotCallTarget(member, mname, "property"):
          if member.len != 2 or member[1].kind != nnkExprEqExpr:
            error("property expects `name = value`", member)
          let key = member[1][0]
          if key.kind notin {nnkIdent, nnkStrLit}:
            error("property name must be an identifier or string", member)
          let pname = key.strVal
          outStmts.add(newCall("setProp", ctxId, copy(nsOf),
            newStrLitNode(pname),
            newCall("propToJS", ctxId,
              substModule(member[1][1], mname, moduleSym)),
            nnkCommand.newTree(newIdentNode("addr"), exSym)))
        else:
          error("only module.property and module.registerFn allowed " &
            "in exportObject", member)
    elif dotCallTarget(stmt, mname, "registerFn") or
        dotCallTarget(stmt, mname, "property"):
      error("member declarations must live in exportObject:", stmt)
    else:
      outStmts.add(substModule(stmt, mname, moduleSym))

  result = newNimNode(nnkProcDef)
  result.add(newIdentNode("install").postfix("*"))
  result.add(newEmptyNode())
  result.add(newEmptyNode())
  let formalOut = newNimNode(nnkFormalParams)
  formalOut.add(newIdentNode("JSObjectRef"))
  formalOut.add(nnkIdentDefs.newTree(ctxId, newIdentNode("JSContextRef"),
    newEmptyNode()))
  formalOut.add(nnkIdentDefs.newTree(newIdentNode("rt"),
    newIdentNode("Runtime"), newEmptyNode()))
  result.add(formalOut)
  result.add(newEmptyNode())
  result.add(newEmptyNode())
  let wrapper = newStmtList()
  wrapper.add(newLetStmt(moduleSym,
    nnkObjConstr.newTree(newIdentNode("Module"),
      nnkExprColonExpr.newTree(newIdentNode("ctx"), ctxId),
      nnkExprColonExpr.newTree(newIdentNode("ns"),
        newCall("newObject", ctxId)))))
  let varSec = newNimNode(nnkVarSection)
  varSec.add(newIdentDefs(exSym, newIdentNode("JSValueRef"),
    newNilLit()))
  wrapper.add(varSec)
  for s in outStmts:
    wrapper.add(s)
  let cond = newNimNode(nnkInfix)
  cond.add(newIdentNode("!="))
  cond.add(exSym)
  cond.add(newNilLit())
  let retNil = newNimNode(nnkReturnStmt)
  retNil.add(newNilLit())
  let elifBranch = nnkElifBranch.newTree(cond, newStmtList(retNil))
  wrapper.add(nnkIfStmt.newTree(elifBranch))
  wrapper.add(nsOf)
  result.add(wrapper)
