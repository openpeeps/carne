# Carne std/csv: CSV parsing via openparser.
#
#   const csv = require("std/csv");
#   csv.parse(text[, {headers, delimiter, quote}]) -> array
#
# Without headers: array of string arrays. With `headers: true` the first
# row becomes keys and the result is an array of objects. openparser's CSV
# reader is MemFile-based, so input goes through a temp file.

import std/[json, os]

import javascriptcore

import pkg/openparser/csv

import ../bridge

## Builds the std/csv namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn parse:
      ## csv.parse(text[, {headers, delimiter, quote}]) -> array
      if not checkArity(argumentCount, 1, 2, "parse", ctx, exception):
        return nil
      var text: string
      if not strArg(ctx, args, 0, "parse", exception, text):
        return nil
      var headers = false
      var opts = defaultCsvOptions()
      if int(argumentCount) >= 2:
        var v: NimValue
        if not nimArg(ctx, args, 1, "parse", exception, v):
          return nil
        if v.kind != nvkObject:
          throwError(ctx, "parse: options must be an object", exception)
          return nil
        if v.hasKey("headers") and v.get("headers", "parse").kind == nvkBool:
          headers = v.get("headers", "parse").b
        if v.hasKey("delimiter"):
          let d = v.get("delimiter", "parse")
          if d.kind == nvkString and d.s.len > 0:
            opts.delimiter = d.s[0]
        if v.hasKey("quote"):
          let q = v.get("quote", "parse")
          if q.kind == nvkString and q.s.len > 0:
            opts.quote = q.s[0]
      let tmp = getTempDir() / "carne_csv_parse.tmp"
      try:
        writeFile(tmp, text)
      except IOError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        return nil
      except OSError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        return nil
      var rows: seq[seq[string]] = @[]
      try:
        proc onRow(fields: openArray[CsvFieldSlice], row: int): bool =
          var r: seq[string] = @[]
          for f in fields:
            r.add($f)
          rows.add(r)
          true
        parseFile(tmp, onRow, opts)
      except CatchableError as e:
        try: removeFile(tmp)
        except OSError: discard
        throwError(ctx, "parse: " & e.msg, exception)
        return nil
      try: removeFile(tmp)
      except OSError: discard
      try:
        let arr = newJArray()
        if headers and rows.len > 0:
          let heads = rows[0]
          for r in rows[1 .. ^1]:
            let obj = newJObject()
            for i, h in heads:
              obj[h] = %(if i < r.len: r[i] else: "")
            arr.add(obj)
        elif not headers:
          for r in rows:
            let a = newJArray()
            for f in r:
              a.add(%f)
            arr.add(a)
        returnJson(ctx, arr, "parse", exception)
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil
