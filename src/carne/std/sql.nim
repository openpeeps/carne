# Carne std/sql: SQL parsing and validation via openparser.
#
#   const sql = require("std/sql");
#   sql.sqlite.parse("SELECT a FROM t")   -> AST object
#   sql.postgres.validate("SELECT $1")    -> {valid: true}
#   sql.mysql.validate("SELECT `a` FROM t") -> {valid: true}
#
# One sub-namespace per dialect: sqlite, postgres (= pgsql), mysql.
# Each has parse(sql) -> AST and validate(sql) -> {valid, error?}.
# parse throws a JS Error on syntax errors; validate never throws,
# it reports {valid: false, error: "..."} instead.
#
# AST shape: {kind, value?, quote?, children?}. kind is the openparser
# SqlNodeKind without the "nk" prefix ("Select", "StmtList", ...).
# Literal nodes carry value (and quote for quoted idents/strings:
# "Single", "Double", "Backtick", "Bracket"); every other node
# carries children.
#
# The three namespaces are built as setup (the DSL attaches members
# to the top namespace only), with define-only `ctx.registerFn`
# callbacks sharing one helper per operation.

import javascriptcore

import pkg/openparser/sql

import ../bridge

const literalKinds = {nkIdent, nkQuotedIdent, nkStringLit, nkBitStringLit,
  nkHexStringLit, nkIntegerLit, nkNumericLit, nkPlaceholder, nkRaw}

proc sqlToJS(ctx: JSContextRef; n: SqlNode; name: string;
    exception: ptr JSValueRef): JSValueRef =
  ## SqlNode -> live JS value, no JsonNode middle layer.
  let obj = newObject(ctx)
  if not setPropChecked(ctx, obj, "kind", toJS(ctx, ($n.kind)[2 .. ^1]),
      name, exception):
    return nil
  if n.kind in literalKinds:
    if not setPropChecked(ctx, obj, "value", toJS(ctx, n.strVal),
        name, exception):
      return nil
    if n.quote != qkNone:
      if not setPropChecked(ctx, obj, "quote",
          toJS(ctx, ($n.quote)[2 .. ^1]), name, exception):
        return nil
  else:
    var vals: seq[JSValueRef] = @[]
    for child in n.sons:
      let j = sqlToJS(ctx, child, name, exception)
      if j == nil:
        return nil
      vals.add(j)
    let kids = makeJSArray(ctx, vals)
    if kids == nil:
      throwError(ctx, name & ": could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "children", kids, name, exception):
      return nil
  result = obj

proc sqlErr(ctx: JSContextRef; docBlock, name, detail: string;
    exception: ptr JSValueRef) =
  ## Domain-error throw with the JSDoc block first (CLI info).
  var msg = ""
  if docBlock.len > 0:
    msg = docBlock & "\n"
  throwError(ctx, msg & name & ": " & detail, exception)

proc doParse(ctx: JSContextRef; text: string; driver: SqlDriver;
    name, docBlock: string; exception: ptr JSValueRef): JSValueRef =
  try:
    let j = sqlToJS(ctx, parseSql(text, driver), name, exception)
    if j == nil:
      sqlErr(ctx, docBlock, name, "could not convert result to JS",
        exception)
      return nil
    j
  except CatchableError as e:
    # SqlParseError text starts with a newline + code snippet.
    sqlErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doValidate(ctx: JSContextRef; text: string; driver: SqlDriver;
    name, docBlock: string; exception: ptr JSValueRef): JSValueRef =
  try:
    discard parseSql(text, driver)
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "valid", toJS(ctx, true), name,
        exception):
      sqlErr(ctx, docBlock, name, "could not convert result to JS",
        exception)
      return nil
    obj
  except CatchableError as e:
    let obj = newObject(ctx)
    if not setPropChecked(ctx, obj, "valid", toJS(ctx, false), name,
        exception):
      sqlErr(ctx, docBlock, name, "could not convert result to JS",
        exception)
      return nil
    if not setPropChecked(ctx, obj, "error", toJS(ctx, e.msg), name,
        exception):
      sqlErr(ctx, docBlock, name, "could not convert result to JS",
        exception)
      return nil
    obj

## Builds the std/sql namespace object.
init proc(module: Module) =
  let sqliteNs = newObject(module.ctx)
  let postgresNs = newObject(module.ctx)
  let mysqlNs = newObject(module.ctx)

  ctx.registerFn sqliteParse(sql: string):
    ## sqlite.parse(sql) -> AST object
    return doParse(ctx, sql, sqlite, "sqlite.parse", docBlock, exception)

  ctx.registerFn sqliteValidate(sql: string):
    ## sqlite.validate(sql) -> {valid, error?}
    return doValidate(ctx, sql, sqlite, "sqlite.validate", docBlock, exception)

  ctx.registerFn postgresParse(sql: string):
    ## postgres.parse(sql) -> AST object
    return doParse(ctx, sql, pgsql, "postgres.parse", docBlock, exception)

  ctx.registerFn postgresValidate(sql: string):
    ## postgres.validate(sql) -> {valid, error?}
    return doValidate(ctx, sql, pgsql, "postgres.validate", docBlock, exception)

  ctx.registerFn mysqlParse(sql: string):
    ## mysql.parse(sql) -> AST object
    return doParse(ctx, sql, mysql, "mysql.parse", docBlock, exception)

  ctx.registerFn mysqlValidate(sql: string):
    ## mysql.validate(sql) -> {valid, error?}
    return doValidate(ctx, sql, mysql, "mysql.validate", docBlock, exception)

  # Plain-object property sets cannot throw; no setupEx in scope here.
  setProp(module.ctx, sqliteNs, "parse",
    makeFunction(module.ctx, "parse", sqliteParse), nil)
  setProp(module.ctx, sqliteNs, "validate",
    makeFunction(module.ctx, "validate", sqliteValidate), nil)
  setProp(module.ctx, postgresNs, "parse",
    makeFunction(module.ctx, "parse", postgresParse), nil)
  setProp(module.ctx, postgresNs, "validate",
    makeFunction(module.ctx, "validate", postgresValidate), nil)
  setProp(module.ctx, mysqlNs, "parse",
    makeFunction(module.ctx, "parse", mysqlParse), nil)
  setProp(module.ctx, mysqlNs, "validate",
    makeFunction(module.ctx, "validate", mysqlValidate), nil)

  setProp(module.ctx, module.ns, "sqlite", sqliteNs, nil)
  setProp(module.ctx, module.ns, "postgres", postgresNs, nil)
  setProp(module.ctx, module.ns, "mysql", mysqlNs, nil)
