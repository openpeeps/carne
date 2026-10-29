# Carne std/crypto: hashing, AEAD sealing, signatures and passwords.
#
#   const crypto = require("std/crypto");
#   crypto.hash.sha256hex("abc")     -> hex digest (lowercase)
#   crypto.aead.seal(text, keyHex)   -> {nonce, mac, cipher} (hex)
#   crypto.aead.open(env, keyHex)    -> text (throws on MAC failure)
#   crypto.sign.keypair()            -> {publicKey, secretKey} hex
#   crypto.sign.sign(secretHex, msg) -> sigHex (ed25519)
#   crypto.sign.verify(pubHex, msg, sigHex) -> bool
#   crypto.password.hash(pw)         -> "hex(salt):hex(hash)" (argon2id)
#   crypto.password.verify(pw, stored) -> bool
#
# All binary values cross the boundary as lowercase hex strings.
# Hex input is case-insensitive. Keys/sigs/envelopes are length-checked
# with explicit errors. `open` throws on MAC failure; `verify` returns
# false on mismatch instead (verification is not exceptional), and
# `password.verify` returns false on malformed stored strings.
#
# X25519/RSA/ECDSA and AES modes are deferred to a later pass.
# Like std/sql, the four groups are built as setup with define-only
# `ctx.registerFn` callbacks sharing one helper per operation.

import std/[json, strutils]

import javascriptcore

import pkg/nimcypher/[hash, encrypt, sign, password, utils]

import ../bridge

proc hexOut(data: openArray[byte]): string =
  ## nimcypher hex is uppercase; the JS side is lowercase.
  toHex(data).toLowerAscii()

proc parseBytes(s, field: string): seq[byte] =
  ## Variable-length hex -> bytes. Raises ValueError with context.
  ## Callers prefix the function name.
  if s.len == 0 or s.len mod 2 != 0:
    raise newException(ValueError, field & " must be non-empty even-length hex")
  result = newSeq[byte](s.len div 2)
  try:
    for i in 0 ..< result.len:
      result[i] = byte(parseHexInt(s[i * 2 .. i * 2 + 1]))
  except ValueError:
    raise newException(ValueError, field & " is not valid hex")

proc parseKey32(s: string): Key32 =
  if s.len != 64:
    raise newException(ValueError, "key must be 64 hex chars (32 bytes)")
  try:
    fromHex[32, uint8](s)
  except ValueError:
    raise newException(ValueError, "key is not valid hex")

proc getArgs(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef;
    name, usage: string; wantMin, wantMax: int):
    ptr UncheckedArray[JSValueRef] =
  ## Arity check shared by every helper. nil on failure.
  if not checkArity(argumentCount, wantMin, wantMax, name, ctx, exception,
      usage):
    return nil
  cast[ptr UncheckedArray[JSValueRef]](arguments)

# -- hash ------------------------------------------------------------

proc doSha256(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "hash.sha256hex"
  const usage = "hash.sha256hex(text) -> hex digest"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 1, 1)
  if args == nil:
    return nil
  var text: string
  if not strArg(ctx, args, 0, name, exception, text):
    return nil
  try:
    toJS(ctx, hexOut(sha256(text)))
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

proc doSha384(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "hash.sha384hex"
  const usage = "hash.sha384hex(text) -> hex digest"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 1, 1)
  if args == nil:
    return nil
  var text: string
  if not strArg(ctx, args, 0, name, exception, text):
    return nil
  try:
    toJS(ctx, hexOut(sha384(text)))
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

proc doSha512(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "hash.sha512hex"
  const usage = "hash.sha512hex(text) -> hex digest"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 1, 1)
  if args == nil:
    return nil
  var text: string
  if not strArg(ctx, args, 0, name, exception, text):
    return nil
  try:
    toJS(ctx, hexOut(sha512(text)))
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

proc doBlake2b(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "hash.blake2bhex"
  const usage = "hash.blake2bhex(text[, size]) -> hex digest (size 1..64, default 32)"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 1, 2)
  if args == nil:
    return nil
  var text: string
  if not strArg(ctx, args, 0, name, exception, text):
    return nil
  var size = Blake2bDefaultDigestSize
  if int(argumentCount) == 2:
    var sizeNum = 0.0
    if not numArg(ctx, args, 1, name, exception, sizeNum):
      return nil
    if not (sizeNum >= 1.0 and sizeNum <= 64.0 and
        sizeNum == float(int(sizeNum))):
      throwError(ctx, name & ": size must be an integer 1..64\n" & usage,
        exception)
      return nil
    size = int(sizeNum)
  try:
    toJS(ctx, blakeHex(text, size).toLowerAscii())
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

proc doHmacSha256(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "hash.hmacSha256hex"
  const usage = "hash.hmacSha256hex(keyHex, text) -> hex mac"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 2, 2)
  if args == nil:
    return nil
  var keyHex, text: string
  if not strArg(ctx, args, 0, name, exception, keyHex):
    return nil
  if not strArg(ctx, args, 1, name, exception, text):
    return nil
  try:
    let key = parseBytes(keyHex, "key")
    toJS(ctx, hexOut(sha256Hmac(key, toBytes(text))))
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

# -- aead (XChaCha20-Poly1305) ----------------------------------------

proc doSeal(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "aead.seal"
  const usage = "aead.seal(text, keyHex) -> {nonce, mac, cipher}"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 2, 2)
  if args == nil:
    return nil
  var text, keyHex: string
  if not strArg(ctx, args, 0, name, exception, text):
    return nil
  if not strArg(ctx, args, 1, name, exception, keyHex):
    return nil
  try:
    let msg = seal(text, parseKey32(keyHex))
    returnJson(ctx, %*{"nonce": hexOut(msg.nonce), "mac": hexOut(msg.mac),
      "cipher": hexOut(msg.cipherText)}, name, exception)
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

proc doOpen(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "aead.open"
  const usage = "aead.open({nonce, mac, cipher}, keyHex) -> text"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 2, 2)
  if args == nil:
    return nil
  var envObj: JSValueRef
  if not objArg(ctx, args, 0, name, exception, envObj):
    return nil
  var keyHex: string
  if not strArg(ctx, args, 1, name, exception, keyHex):
    return nil
  try:
    var err = ""
    var nonceHex, macHex, cipherHex: string
    for (field, dst) in [("nonce", addr nonceHex), ("mac", addr macHex),
        ("cipher", addr cipherHex)]:
      let f = getField(ctx, envObj, field, err)
      if err != "":
        raise newException(ValueError, "envelope." & field & " " & err)
      if f.kind != nvkString:
        raise newException(ValueError, "envelope needs hex \"" & field & "\"")
      dst[] = f.s
    if nonceHex.len != 48:
      raise newException(ValueError,
        "envelope.nonce must be 48 hex chars (24 bytes)")
    if macHex.len != 32:
      raise newException(ValueError,
        "envelope.mac must be 32 hex chars (16 bytes)")
    let msg = SealedMessage(nonce: fromHex[24, uint8](nonceHex),
      mac: fromHex[16, uint8](macHex),
      cipherText: parseBytes(cipherHex, "envelope.cipher"))
    toJS(ctx, toString(unseal(msg, parseKey32(keyHex))))
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

# -- sign (ed25519) ---------------------------------------------------

proc doKeypair(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "sign.keypair"
  const usage = "sign.keypair() -> {publicKey, secretKey} hex"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 0, 0)
  if args == nil:
    return nil
  try:
    let kp = generateSigningKeyPair()
    returnJson(ctx, %*{"publicKey": publicKeyToHex(kp.publicKey).toLowerAscii(),
      "secretKey": secretKeyToHex(kp.secretKey).toLowerAscii()}, name,
      exception)
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

proc doKeypairFromSeed(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "sign.keypairFromSeed"
  const usage = "sign.keypairFromSeed(seedHex) -> {publicKey, secretKey} hex"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 1, 1)
  if args == nil:
    return nil
  var seedHex: string
  if not strArg(ctx, args, 0, name, exception, seedHex):
    return nil
  try:
    if seedHex.len != 64:
      raise newException(ValueError, "seed must be 64 hex chars (32 bytes)")
    let kp = generateSigningKeyPair(fromHex[32, uint8](seedHex))
    returnJson(ctx, %*{"publicKey": publicKeyToHex(kp.publicKey).toLowerAscii(),
      "secretKey": secretKeyToHex(kp.secretKey).toLowerAscii()}, name,
      exception)
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

proc doSign(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "sign.sign"
  const usage = "sign.sign(secretHex, text) -> hex signature"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 2, 2)
  if args == nil:
    return nil
  var secretHex, text: string
  if not strArg(ctx, args, 0, name, exception, secretHex):
    return nil
  if not strArg(ctx, args, 1, name, exception, text):
    return nil
  try:
    let sig = sign(secretKeyFromHex(secretHex), text)
    toJS(ctx, signatureToHex(sig).toLowerAscii())
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

proc doVerify(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "sign.verify"
  const usage = "sign.verify(publicHex, text, sigHex) -> bool"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 3, 3)
  if args == nil:
    return nil
  var publicHex, text, sigHex: string
  if not strArg(ctx, args, 0, name, exception, publicHex):
    return nil
  if not strArg(ctx, args, 1, name, exception, text):
    return nil
  if not strArg(ctx, args, 2, name, exception, sigHex):
    return nil
  try:
    toJS(ctx, verify(publicKeyFromHex(publicHex), text,
      signatureFromHex(sigHex)))
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

# -- password (argon2id) -----------------------------------------------

proc doPwHash(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "password.hash"
  const usage = "password.hash(pw) -> \"hex(salt):hex(hash)\""
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 1, 1)
  if args == nil:
    return nil
  var pw: string
  if not strArg(ctx, args, 0, name, exception, pw):
    return nil
  try:
    # nimcypher hex is uppercase; the JS side is lowercase (verify
    # accepts both, so stored strings stay interoperable).
    toJS(ctx, hashPassword(pw).toLowerAscii())
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

proc doPwVerify(ctx: JSContextRef; argumentCount: csize_t;
    arguments: ptr JSValueRef; exception: ptr JSValueRef): JSValueRef =
  const name = "password.verify"
  const usage = "password.verify(pw, stored) -> bool"
  let args = getArgs(ctx, argumentCount, arguments, exception, name,
    usage, 2, 2)
  if args == nil:
    return nil
  var pw, stored: string
  if not strArg(ctx, args, 0, name, exception, pw):
    return nil
  if not strArg(ctx, args, 1, name, exception, stored):
    return nil
  try:
    toJS(ctx, verifyPassword(pw, stored))
  except CatchableError as e:
    throwError(ctx, name & ": " & e.msg & "\n" & usage, exception)
    nil

## Builds the std/crypto namespace object.
init proc(module: Module) =
  let hashNs = newObject(module.ctx)
  let aeadNs = newObject(module.ctx)
  let signNs = newObject(module.ctx)
  let passwordNs = newObject(module.ctx)

  ctx.registerFn hashSha256:
    ## hash.sha256hex(text) -> hex digest
    return doSha256(ctx, argumentCount, arguments, exception)

  ctx.registerFn hashSha384:
    ## hash.sha384hex(text) -> hex digest
    return doSha384(ctx, argumentCount, arguments, exception)

  ctx.registerFn hashSha512:
    ## hash.sha512hex(text) -> hex digest
    return doSha512(ctx, argumentCount, arguments, exception)

  ctx.registerFn hashBlake2b:
    ## hash.blake2bhex(text[, size]) -> hex digest (size 1..64, default 32)
    return doBlake2b(ctx, argumentCount, arguments, exception)

  ctx.registerFn hashHmacSha256:
    ## hash.hmacSha256hex(keyHex, text) -> hex mac
    return doHmacSha256(ctx, argumentCount, arguments, exception)

  ctx.registerFn aeadSeal:
    ## aead.seal(text, keyHex) -> {nonce, mac, cipher}
    return doSeal(ctx, argumentCount, arguments, exception)

  ctx.registerFn aeadOpen:
    ## aead.open({nonce, mac, cipher}, keyHex) -> text
    return doOpen(ctx, argumentCount, arguments, exception)

  ctx.registerFn signKeypair:
    ## sign.keypair() -> {publicKey, secretKey} hex
    return doKeypair(ctx, argumentCount, arguments, exception)

  ctx.registerFn signKeypairFromSeed:
    ## sign.keypairFromSeed(seedHex) -> {publicKey, secretKey} hex
    return doKeypairFromSeed(ctx, argumentCount, arguments, exception)

  ctx.registerFn signSign:
    ## sign.sign(secretHex, text) -> hex signature
    return doSign(ctx, argumentCount, arguments, exception)

  ctx.registerFn signVerify:
    ## sign.verify(publicHex, text, sigHex) -> bool
    return doVerify(ctx, argumentCount, arguments, exception)

  ctx.registerFn passwordHash:
    ## password.hash(pw) -> "hex(salt):hex(hash)"
    return doPwHash(ctx, argumentCount, arguments, exception)

  ctx.registerFn passwordVerify:
    ## password.verify(pw, stored) -> bool
    return doPwVerify(ctx, argumentCount, arguments, exception)

  # Plain-object property sets cannot throw; no setupEx in scope here.
  setProp(module.ctx, hashNs, "sha256hex",
    makeFunction(module.ctx, "sha256hex", hashSha256), nil)
  setProp(module.ctx, hashNs, "sha384hex",
    makeFunction(module.ctx, "sha384hex", hashSha384), nil)
  setProp(module.ctx, hashNs, "sha512hex",
    makeFunction(module.ctx, "sha512hex", hashSha512), nil)
  setProp(module.ctx, hashNs, "blake2bhex",
    makeFunction(module.ctx, "blake2bhex", hashBlake2b), nil)
  setProp(module.ctx, hashNs, "hmacSha256hex",
    makeFunction(module.ctx, "hmacSha256hex", hashHmacSha256), nil)

  setProp(module.ctx, aeadNs, "seal",
    makeFunction(module.ctx, "seal", aeadSeal), nil)
  setProp(module.ctx, aeadNs, "open",
    makeFunction(module.ctx, "open", aeadOpen), nil)

  setProp(module.ctx, signNs, "keypair",
    makeFunction(module.ctx, "keypair", signKeypair), nil)
  setProp(module.ctx, signNs, "keypairFromSeed",
    makeFunction(module.ctx, "keypairFromSeed", signKeypairFromSeed), nil)
  setProp(module.ctx, signNs, "sign",
    makeFunction(module.ctx, "sign", signSign), nil)
  setProp(module.ctx, signNs, "verify",
    makeFunction(module.ctx, "verify", signVerify), nil)

  setProp(module.ctx, passwordNs, "hash",
    makeFunction(module.ctx, "hash", passwordHash), nil)
  setProp(module.ctx, passwordNs, "verify",
    makeFunction(module.ctx, "verify", passwordVerify), nil)

  setProp(module.ctx, module.ns, "hash", hashNs, nil)
  setProp(module.ctx, module.ns, "aead", aeadNs, nil)
  setProp(module.ctx, module.ns, "sign", signNs, nil)
  setProp(module.ctx, module.ns, "password", passwordNs, nil)
