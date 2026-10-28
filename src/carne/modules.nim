# Carne module registry: `require("std/<name>")` with lazy install.
#
# Adding a stdlib = one file under std/ exposing
# `install*(ctx: JSContextRef; rt: Runtime): JSObjectRef`,
# plus one row in the installers table below.

import std/tables

import javascriptcore

import ./bridge
import ./std/env
import ./std/fs
import ./std/yaml
import ./std/toml
import ./std/ical
import ./std/dotenv
import ./std/plist
import ./std/bson
import ./std/vcard
import ./std/feed
import ./std/csv
import ./std/xml
import ./std/sql
import ./std/crypto
import ./std/path
import ./std/colors
import ./std/css
import ./std/diff
import ./std/gettext
import ./std/regex
import ./std/qr
import ./std/svg
import ./std/http

type
  Installer* = proc(ctx: JSContextRef; rt: Runtime): JSObjectRef

let installers* = {
  "std/env": Installer(env.install),
  "std/fs": Installer(fs.install),
  "std/yaml": Installer(yaml.install),
  "std/toml": Installer(toml.install),
  "std/ical": Installer(ical.install),
  "std/dotenv": Installer(dotenv.install),
  "std/plist": Installer(plist.install),
  "std/bson": Installer(bson.install),
  "std/vcard": Installer(vcard.install),
  "std/feed": Installer(feed.install),
  "std/csv": Installer(csv.install),
  "std/xml": Installer(xml.install),
  "std/sql": Installer(sql.install),
  "std/crypto": Installer(crypto.install),
  "std/path": Installer(path.install),
  "std/colors": Installer(colors.install),
  "std/css": Installer(css.install),
  "std/diff": Installer(diff.install),
  "std/gettext": Installer(gettext.install),
  "std/regex": Installer(regex.install),
  "std/qr": Installer(qr.install),
  "std/svg": Installer(svg.install),
  "std/http": Installer(http.install),
}.toTable

proc requireImpl(ctx: JSContextRef; function, thisObject: JSObjectRef;
    argumentCount: csize_t; arguments: ptr JSValueRef;
    exception: ptr JSValueRef): JSValueRef {.cdecl.} =
  ## Implements global require(spec).
  if not checkArity(argumentCount, 1, 1, "require", ctx, exception):
    return nil
  let args = cast[ptr UncheckedArray[JSValueRef]](arguments)
  var spec: string
  if not strArg(ctx, args, 0, "require", exception, spec):
    return nil
  let rt = currentRt()
  if rt.instances.hasKey(spec):
    return rt.instances[spec]
  if not installers.hasKey(spec):
    throwError(ctx, "require: unknown module \"" & spec & "\"", exception)
    return nil
  let ns = installers[spec](ctx, rt)
  if ns == nil:
    throwError(ctx, "require: failed to initialize \"" & spec & "\"",
      exception)
    return nil
  rt.instances[spec] = ns
  ns

proc installRequire*(rt: Runtime; setupEx: ptr JSValueRef) =
  ## Installs the global require function.
  let global = JSContextGetGlobalObject(rt.ctx)
  setProp(rt.ctx, global, "require",
    makeFunction(rt.ctx, "require", requireImpl), setupEx)
