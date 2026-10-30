# Carne std/uuid: UUID generation and inspection via openparser.
#
#   const {uuid4} = require("std/uuid");
#   uuid4()                       -> "f47ac10b-58cc-4372-a567-0e02b2c3d479"
#   const uuid = require("std/uuid");
#   uuid.v4()                     -> same (v1..v8 aliases for uuid1..uuid8)
#   uuid.v7()                     -> time-ordered Unix-ms UUID
#   uuid.v3(uuid.NAMESPACE_DNS, "example.com") -> deterministic (MD5)
#   uuid.v5(uuid.NAMESPACE_URL, "https://x.io") -> deterministic (SHA-1)
#   uuid.parse("F47AC10B58CC4372A5670E02B2C3D479") -> normalized lowercase
#   uuid.isValid("nope")          -> false
#   uuid.version(uuid.v4())       -> 4
#   uuid.variant(uuid.v4())       -> "rfc4122"
#   uuid.isNil(uuid.NIL)          -> true
#
# uuid2(domain, localId) is DCE Security (domain 0..255, localId
# 0..4294967295). uuid8(data) takes 32 hex chars (dashes allowed) as
# custom payload; version/variant bits are overwritten. parse,
# version, variant and isNil throw a JS Error on invalid input;
# isValid never throws.

import javascriptcore

import pkg/openparser/uuid

import ../bridge

proc variantName(v: UuidVariant): string =
  case v
  of variantNCS: "ncs"
  of variantRFC4122: "rfc4122"
  of variantMicrosoft: "microsoft"
  of variantFuture: "future"

## Builds the std/uuid namespace object.
init proc(module: Module) =
  exportObject:

    module.registerFn uuid1():
      ## uuid.uuid1() -> time-based v1 UUID string
      toJS(ctx, $newUuidV1())

    module.registerFn v1():
      ## uuid.v1() -> time-based v1 UUID string (alias for uuid1)
      toJS(ctx, $newUuidV1())

    module.registerFn uuid2(domain: int, localId: int):
      ## uuid.uuid2(domain, localId) -> DCE Security v2 UUID string
      try:
        if domain < 0 or domain > 255:
          throwError(ctx, "uuid2: domain out of range (0..255)", exception)
          return nil
        if localId < 0 or localId > 0xFFFFFFFF:
          throwError(ctx, "uuid2: localId out of range (0..4294967295)",
            exception)
          return nil
        toJS(ctx, $newUuidV2(byte(domain), uint32(localId)))
      except CatchableError as e:
        throwError(ctx, "uuid2: " & e.msg, exception)
        nil

    module.registerFn v2(domain: int, localId: int):
      ## uuid.v2(domain, localId) -> DCE Security v2 UUID string (alias)
      try:
        if domain < 0 or domain > 255:
          throwError(ctx, "v2: domain out of range (0..255)", exception)
          return nil
        if localId < 0 or localId > 0xFFFFFFFF:
          throwError(ctx, "v2: localId out of range (0..4294967295)",
            exception)
          return nil
        toJS(ctx, $newUuidV2(byte(domain), uint32(localId)))
      except CatchableError as e:
        throwError(ctx, "v2: " & e.msg, exception)
        nil

    module.registerFn uuid3(namespace: string, name: string):
      ## uuid.uuid3(namespace, name) -> MD5 name-based v3 UUID string
      try:
        toJS(ctx, $newUuidV3(parseUuid(namespace), name))
      except CatchableError as e:
        throwError(ctx, "uuid3: " & e.msg, exception)
        nil

    module.registerFn v3(namespace: string, name: string):
      ## uuid.v3(namespace, name) -> MD5 name-based v3 UUID string (alias)
      try:
        toJS(ctx, $newUuidV3(parseUuid(namespace), name))
      except CatchableError as e:
        throwError(ctx, "v3: " & e.msg, exception)
        nil

    module.registerFn uuid4():
      ## uuid.uuid4() -> random v4 UUID string
      try:
        toJS(ctx, $newUuidV4())
      except CatchableError as e:
        throwError(ctx, "uuid4: " & e.msg, exception)
        nil

    module.registerFn v4():
      ## uuid.v4() -> random v4 UUID string (alias for uuid4)
      try:
        toJS(ctx, $newUuidV4())
      except CatchableError as e:
        throwError(ctx, "v4: " & e.msg, exception)
        nil

    module.registerFn uuid5(namespace: string, name: string):
      ## uuid.uuid5(namespace, name) -> SHA-1 name-based v5 UUID string
      try:
        toJS(ctx, $newUuidV5(parseUuid(namespace), name))
      except CatchableError as e:
        throwError(ctx, "uuid5: " & e.msg, exception)
        nil

    module.registerFn v5(namespace: string, name: string):
      ## uuid.v5(namespace, name) -> SHA-1 name-based v5 UUID string (alias)
      try:
        toJS(ctx, $newUuidV5(parseUuid(namespace), name))
      except CatchableError as e:
        throwError(ctx, "v5: " & e.msg, exception)
        nil

    module.registerFn uuid6():
      ## uuid.uuid6() -> reordered-timestamp v6 UUID string
      toJS(ctx, $newUuidV6())

    module.registerFn v6():
      ## uuid.v6() -> reordered-timestamp v6 UUID string (alias for uuid6)
      toJS(ctx, $newUuidV6())

    module.registerFn uuid7():
      ## uuid.uuid7() -> Unix-ms time-ordered v7 UUID string
      try:
        toJS(ctx, $newUuidV7())
      except CatchableError as e:
        throwError(ctx, "uuid7: " & e.msg, exception)
        nil

    module.registerFn v7():
      ## uuid.v7() -> Unix-ms time-ordered v7 UUID string (alias for uuid7)
      try:
        toJS(ctx, $newUuidV7())
      except CatchableError as e:
        throwError(ctx, "v7: " & e.msg, exception)
        nil

    module.registerFn uuid8(data: string):
      ## uuid.uuid8(data) -> custom v8 UUID string (32 hex chars, dashes ok)
      try:
        toJS(ctx, $newUuidV8(parseUuid(data).bytes))
      except CatchableError as e:
        throwError(ctx, "uuid8: " & e.msg, exception)
        nil

    module.registerFn v8(data: string):
      ## uuid.v8(data) -> custom v8 UUID string (alias for uuid8)
      try:
        toJS(ctx, $newUuidV8(parseUuid(data).bytes))
      except CatchableError as e:
        throwError(ctx, "v8: " & e.msg, exception)
        nil

    module.registerFn parse(s: string):
      ## uuid.parse(s) -> normalized lowercase UUID string (throws if invalid)
      try:
        toJS(ctx, $parseUuid(s))
      except CatchableError as e:
        throwError(ctx, "parse: " & e.msg, exception)
        nil

    module.registerFn isValid(s: string):
      ## uuid.isValid(s) -> bool
      toJS(ctx, isValidUuid(s))

    module.registerFn version(s: string):
      ## uuid.version(s) -> version number 1..8 (throws if invalid)
      try:
        toJS(ctx, parseUuid(s).version())
      except CatchableError as e:
        throwError(ctx, "version: " & e.msg, exception)
        nil

    module.registerFn variant(s: string):
      ## uuid.variant(s) -> "ncs" | "rfc4122" | "microsoft" | "future"
      try:
        toJS(ctx, variantName(parseUuid(s).variant()))
      except CatchableError as e:
        throwError(ctx, "variant: " & e.msg, exception)
        nil

    module.registerFn isNil(s: string):
      ## uuid.isNil(s) -> true for the all-zeros UUID (throws if invalid)
      try:
        toJS(ctx, parseUuid(s).isNil())
      except CatchableError as e:
        throwError(ctx, "isNil: " & e.msg, exception)
        nil

  setProp(module.ctx, module.ns, "NIL",
    toJS(module.ctx, $nilUuid()), nil)
  setProp(module.ctx, module.ns, "NAMESPACE_DNS",
    toJS(module.ctx, $nsDNS), nil)
  setProp(module.ctx, module.ns, "NAMESPACE_URL",
    toJS(module.ctx, $nsURL), nil)
  setProp(module.ctx, module.ns, "NAMESPACE_OID",
    toJS(module.ctx, $nsOID), nil)
  setProp(module.ctx, module.ns, "NAMESPACE_X500",
    toJS(module.ctx, $nsX500), nil)
