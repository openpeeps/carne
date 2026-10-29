import std/strutils
import std/tables
import unittest

import javascriptcore

import pkg/openparser/json

import carne

test "jsTypeName maps kinds to JS names":
  check jsTypeName(nvkUndefined) == "undefined"
  check jsTypeName(nvkNull) == "null"
  check jsTypeName(nvkBool) == "boolean"
  check jsTypeName(nvkInt) == "number"
  check jsTypeName(nvkFloat) == "number"
  check jsTypeName(nvkString) == "string"
  check jsTypeName(nvkArray) == "object"
  check jsTypeName(nvkObject) == "object"
  check jsTypeName(nvkFunction) == "function"
  check jsTypeName(nvkSymbol) == "symbol"
  check jsTypeName(nvkBigInt) == "bigint"

test "fromJsonNode and toJsonNode roundtrip":
  let node = fromJsonNode(%*{"a": 1, "b": [true, "x"], "c": nil})
  check node.kind == nvkObject
  check node.get("a", "t").asInt("t") == 1
  check toJsonNode(node) == %*{"a": 1, "b": [true, "x"], "c": nil}

test "toJsonNode rejects non-JSON kinds":
  expect CatchableError:
    discard toJsonNode(NimValue(kind: nvkUndefined))
  expect CatchableError:
    discard toJsonNode(NimValue(kind: nvkFunction, raw: nil))
  expect CatchableError:
    discard toJsonNode(NimValue(kind: nvkFloat, f: 0.0 / 0.0))

test "accessors are strict":
  let s = NimValue(kind: nvkString, s: "hi")
  check s.asString("t") == "hi"
  expect CatchableError:
    discard s.asInt("t")
  let f = NimValue(kind: nvkFloat, f: 2.5)
  check f.asFloat("t") == 2.5
  expect CatchableError:
    discard f.asInt("t")
  let whole = NimValue(kind: nvkFloat, f: 3.0)
  check whole.asInt("t") == 3
  let o = NimValue(kind: nvkObject,
    obj: {"k": NimValue(kind: nvkBool, b: true)}.toOrderedTable)
  check o.hasKey("k")
  check not o.hasKey("missing")
  check o.get("k", "t").asBool("t")
  expect CatchableError:
    discard o.get("missing", "t")
  check o.getOpt("missing",
    NimValue(kind: nvkInt, i: 7)).asInt("t") == 7

proc snap(code: string): NimValue =
  ## Evaluates code in a scratch context and snapshots the result.
  withGlobalContext(ctx):
    var ex: JSValueRef = nil
    let v = evalScript(ctx, code, exception = ex)
    check ex == nil
    var err = ""
    let nv = fromJS(ctx, v, err)
    check err == ""
    return nv

test "fromJS snapshots primitives with int/float split":
  check snap("42").kind == nvkInt
  check snap("42").i == 42
  check snap("4.5").kind == nvkFloat
  check snap("'hi'").s == "hi"
  check snap("true").b == true
  check snap("null").kind == nvkNull
  check snap("undefined").kind == nvkUndefined
  check snap("1e21").kind == nvkFloat

test "fromJS snapshots arrays and objects deeply":
  let v = snap("({a: 1, b: [1, 'x', null]})")
  check v.kind == nvkObject
  check v.get("a", "t").i == 1
  check v.get("b", "t").asArray("t").len == 3
  check v.get("b", "t").asArray("t")[2].kind == nvkNull

test "fromJS keeps functions as raw refs":
  let v = snap("((x) => x)")
  check v.kind == nvkFunction
  check v.raw != nil

test "toJS roundtrips a snapshot":
  withGlobalContext(ctx):
    var t = initOrderedTable[string, NimValue]()
    t["n"] = NimValue(kind: nvkInt, i: 3)
    t["s"] = NimValue(kind: nvkString, s: "x")
    let v = NimValue(kind: nvkObject, obj: t)
    let j = toJS(ctx, v)
    check j != nil
    check valueToString(ctx, j) == "[object Object]"
    var err = ""
    let back = fromJS(ctx, j, err)
    check err == ""
    check toJsonNode(back) == toJsonNode(v)

test "toJS preserves NaN through JSC":
  withGlobalContext(ctx):
    let j = toJS(ctx, NimValue(kind: nvkFloat, f: 0.0 / 0.0))
    check j != nil
    var err = ""
    let back = fromJS(ctx, j, err)
    check err == ""
    check back.kind == nvkFloat

test "colors still parses via NimValue arg reader":
  check runCode(
    "JSON.stringify(require('std/colors').parse('red'))") ==
    """{"r":255,"g":0,"b":0,"a":1}"""
  check runCode(
    "const c = require('std/colors');" &
    "c.toHex(c.parse('#333'))") == "#333333"

test "colors rejects mistyped args with type errors":
  try:
    discard runCode("require('std/colors').parse(42)")
    fail()
  except CarneError as e:
    check "expected string" in e.msg
  try:
    discard runCode("require('std/colors').toHex(42)")
    fail()
  except CarneError as e:
    check "must be an {r, g, b, a?} object" in e.msg

test "sql rejects non-strings with a type error":
  try:
    discard runCode("require('std/sql').sqlite.parse(42)")
    fail()
  except CarneError as e:
    check "expected string" in e.msg
