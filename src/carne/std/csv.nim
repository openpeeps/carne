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
        var err = ""
        let o = jsToJson(ctx, args[1], err)
        if o == nil:
          throwError(ctx, "parse: options: " & err, exception)
          return nil
        if o.kind != JObject:
          throwError(ctx, "parse: options must be an object", exception)
          return nil
        if o.hasKey("headers") and o["headers"].kind == JBool:
          headers = o["headers"].getBool()
        if o.hasKey("delimiter") and o["delimiter"].kind == JString:
          let d = o["delimiter"].getStr()
          if d.len > 0:
            opts.delimiter = d[0]
        if o.hasKey("quote") and o["quote"].kind == JString:
          let q = o["quote"].getStr()
          if q.len > 0:
            opts.quote = q[0]
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
