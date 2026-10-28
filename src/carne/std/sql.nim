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

import std/json

import javascriptcore

import pkg/openparser/sql

import ../bridge

const literalKinds = {nkIdent, nkQuotedIdent, nkStringLit, nkBitStringLit,
  nkHexStringLit, nkIntegerLit, nkNumericLit, nkPlaceholder, nkRaw}

proc sqlToJson(n: SqlNode): JsonNode =
  result = newJObject()
  result["kind"] = %($n.kind)[2 .. ^1]
  if n.kind in literalKinds:
    result["value"] = %n.strVal
    if n.quote != qkNone:
      result["quote"] = %($n.quote)[2 .. ^1]
  else:
    var kids = newJArray()
    for child in n.sons:
      kids.add(sqlToJson(child))
    result["children"] = kids

proc doParse(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef;
    driver: SqlDriver; name: string): JSValueRef =
  let usage = name & "(sql) -> AST object"
  if not checkArity(argumentCount, 1, 1, name, ctx, exception, usage):
    return nil
  let args = cast[ptr UncheckedArray[JSValueRef]](arguments)
  var text: string
  if not strArg(ctx, args, 0, name, exception, text):
    return nil
  try:
    returnJson(ctx, sqlToJson(parseSql(text, driver)), name, exception)
  except CatchableError as e:
    # SqlParseError text starts with a newline + code snippet.
    throwError(ctx, name & ":" & e.msg & "\n" & usage, exception)
    nil

proc doValidate(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef;
    driver: SqlDriver; name: string): JSValueRef =
  let usage = name & "(sql) -> {valid, error?}"
  if not checkArity(argumentCount, 1, 1, name, ctx, exception, usage):
    return nil
  let args = cast[ptr UncheckedArray[JSValueRef]](arguments)
  var text: string
  if not strArg(ctx, args, 0, name, exception, text):
    return nil
  try:
    discard parseSql(text, driver)
    returnJson(ctx, %*{"valid": true}, name, exception)
  except CatchableError as e:
    var obj = newJObject()
    obj["valid"] = %false
    obj["error"] = %e.msg
    returnJson(ctx, obj, name, exception)

## Builds the std/sql namespace object.
init proc(module: Module) =
  let sqliteNs = newObject(module.ctx)
  let postgresNs = newObject(module.ctx)
  let mysqlNs = newObject(module.ctx)

  ctx.registerFn sqliteParse:
    ## sqlite.parse(sql) -> AST object
    return doParse(ctx, argumentCount, arguments, exception, sqlite,
      "sqlite.parse")

  ctx.registerFn sqliteValidate:
    ## sqlite.validate(sql) -> {valid, error?}
    return doValidate(ctx, argumentCount, arguments, exception, sqlite,
      "sqlite.validate")

  ctx.registerFn postgresParse:
    ## postgres.parse(sql) -> AST object
    return doParse(ctx, argumentCount, arguments, exception, pgsql,
      "postgres.parse")

  ctx.registerFn postgresValidate:
    ## postgres.validate(sql) -> {valid, error?}
    return doValidate(ctx, argumentCount, arguments, exception, pgsql,
      "postgres.validate")

  ctx.registerFn mysqlParse:
    ## mysql.parse(sql) -> AST object
    return doParse(ctx, argumentCount, arguments, exception, mysql,
      "mysql.parse")

  ctx.registerFn mysqlValidate:
    ## mysql.validate(sql) -> {valid, error?}
    return doValidate(ctx, argumentCount, arguments, exception, mysql,
      "mysql.validate")

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
