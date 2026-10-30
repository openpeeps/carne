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

proc cryptoErr(ctx: JSContextRef; docBlock, name, detail: string;
    exception: ptr JSValueRef) =
  ## Domain-error throw with the JSDoc block first (CLI info).
  var msg = ""
  if docBlock.len > 0:
    msg = docBlock & "\n"
  throwError(ctx, msg & name & ": " & detail, exception)

# -- hash ------------------------------------------------------------

proc doSha256(ctx: JSContextRef; text: string; docBlock: string;
    exception: ptr JSValueRef): JSValueRef =
  const name = "hash.sha256hex"
  try:
    toJS(ctx, hexOut(sha256(text)))
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doSha384(ctx: JSContextRef; text: string; docBlock: string;
    exception: ptr JSValueRef): JSValueRef =
  const name = "hash.sha384hex"
  try:
    toJS(ctx, hexOut(sha384(text)))
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doSha512(ctx: JSContextRef; text: string; docBlock: string;
    exception: ptr JSValueRef): JSValueRef =
  const name = "hash.sha512hex"
  try:
    toJS(ctx, hexOut(sha512(text)))
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doBlake2b(ctx: JSContextRef; text: string; size: int;
    docBlock: string; exception: ptr JSValueRef): JSValueRef =
  const name = "hash.blake2bhex"
  if size < 1 or size > 64:
    cryptoErr(ctx, docBlock, name, "size must be 1..64", exception)
    return nil
  try:
    toJS(ctx, blakeHex(text, size).toLowerAscii())
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doHmacSha256(ctx: JSContextRef; keyHex, text: string;
    docBlock: string; exception: ptr JSValueRef): JSValueRef =
  const name = "hash.hmacSha256hex"
  try:
    let key = parseBytes(keyHex, "key")
    toJS(ctx, hexOut(sha256Hmac(key, toBytes(text))))
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

# -- aead (XChaCha20-Poly1305) ----------------------------------------

proc doSeal(ctx: JSContextRef; text, keyHex: string; docBlock: string;
    exception: ptr JSValueRef): JSValueRef =
  const name = "aead.seal"
  try:
    let msg = seal(text, parseKey32(keyHex))
    returnJson(ctx, %*{"nonce": hexOut(msg.nonce), "mac": hexOut(msg.mac),
      "cipher": hexOut(msg.cipherText)}, name, exception)
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doOpen(ctx: JSContextRef; envObj: JSValueRef; keyHex: string;
    docBlock: string; exception: ptr JSValueRef): JSValueRef =
  const name = "aead.open"
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
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

# -- sign (ed25519) ---------------------------------------------------

proc doKeypair(ctx: JSContextRef; docBlock: string;
    exception: ptr JSValueRef): JSValueRef =
  const name = "sign.keypair"
  try:
    let kp = generateSigningKeyPair()
    returnJson(ctx, %*{"publicKey": publicKeyToHex(kp.publicKey).toLowerAscii(),
      "secretKey": secretKeyToHex(kp.secretKey).toLowerAscii()}, name,
      exception)
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doKeypairFromSeed(ctx: JSContextRef; seedHex: string;
    docBlock: string; exception: ptr JSValueRef): JSValueRef =
  const name = "sign.keypairFromSeed"
  try:
    if seedHex.len != 64:
      raise newException(ValueError, "seed must be 64 hex chars (32 bytes)")
    let kp = generateSigningKeyPair(fromHex[32, uint8](seedHex))
    returnJson(ctx, %*{"publicKey": publicKeyToHex(kp.publicKey).toLowerAscii(),
      "secretKey": secretKeyToHex(kp.secretKey).toLowerAscii()}, name,
      exception)
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doSign(ctx: JSContextRef; secretHex, text: string;
    docBlock: string; exception: ptr JSValueRef): JSValueRef =
  const name = "sign.sign"
  try:
    let sig = sign(secretKeyFromHex(secretHex), text)
    toJS(ctx, signatureToHex(sig).toLowerAscii())
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doVerify(ctx: JSContextRef; publicHex, text, sigHex: string;
    docBlock: string; exception: ptr JSValueRef): JSValueRef =
  const name = "sign.verify"
  try:
    toJS(ctx, verify(publicKeyFromHex(publicHex), text,
      signatureFromHex(sigHex)))
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

# -- password (argon2id) -----------------------------------------------

proc doPwHash(ctx: JSContextRef; pw: string; docBlock: string;
    exception: ptr JSValueRef): JSValueRef =
  const name = "password.hash"
  try:
    # nimcypher hex is uppercase; the JS side is lowercase (verify
    # accepts both, so stored strings stay interoperable).
    toJS(ctx, hashPassword(pw).toLowerAscii())
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

proc doPwVerify(ctx: JSContextRef; pw, stored: string;
    docBlock: string; exception: ptr JSValueRef): JSValueRef =
  const name = "password.verify"
  try:
    toJS(ctx, verifyPassword(pw, stored))
  except CatchableError as e:
    cryptoErr(ctx, docBlock, name, e.msg, exception)
    nil

## Builds the std/crypto namespace object.
init proc(module: Module) =
  let hashNs = newObject(module.ctx)
  let aeadNs = newObject(module.ctx)
  let signNs = newObject(module.ctx)
  let passwordNs = newObject(module.ctx)

  ctx.registerFn hashSha256(text: string):
    ## hash.sha256hex(text) -> hex digest
    return doSha256(ctx, text, docBlock, exception)

  ctx.registerFn hashSha384(text: string):
    ## hash.sha384hex(text) -> hex digest
    return doSha384(ctx, text, docBlock, exception)

  ctx.registerFn hashSha512(text: string):
    ## hash.sha512hex(text) -> hex digest
    return doSha512(ctx, text, docBlock, exception)

  ctx.registerFn hashBlake2b(text: string, size: default(int64, Blake2bDefaultDigestSize)):
    ## hash.blake2bhex(text[, size]) -> hex digest (size 1..64, default 32)
    return doBlake2b(ctx, text, size, docBlock, exception)

  ctx.registerFn hashHmacSha256(keyHex: string, text: string):
    ## hash.hmacSha256hex(keyHex, text) -> hex mac
    return doHmacSha256(ctx, keyHex, text, docBlock, exception)

  ctx.registerFn aeadSeal(text: string, keyHex: string):
    ## aead.seal(text, keyHex) -> {nonce, mac, cipher}
    return doSeal(ctx, text, keyHex, docBlock, exception)

  ctx.registerFn aeadOpen(envObj: JSObjectRef, keyHex: string):
    ## aead.open({nonce, mac, cipher}, keyHex) -> text
    return doOpen(ctx, envObj, keyHex, docBlock, exception)

  ctx.registerFn signKeypair():
    ## sign.keypair() -> {publicKey, secretKey} hex
    return doKeypair(ctx, docBlock, exception)

  ctx.registerFn signKeypairFromSeed(seedHex: string):
    ## sign.keypairFromSeed(seedHex) -> {publicKey, secretKey} hex
    return doKeypairFromSeed(ctx, seedHex, docBlock, exception)

  ctx.registerFn signSign(secretHex: string, text: string):
    ## sign.sign(secretHex, text) -> hex signature
    return doSign(ctx, secretHex, text, docBlock, exception)

  ctx.registerFn signVerify(publicHex: string, text: string, sigHex: string):
    ## sign.verify(publicHex, text, sigHex) -> bool
    return doVerify(ctx, publicHex, text, sigHex, docBlock, exception)

  ctx.registerFn passwordHash(pw: string):
    ## password.hash(pw) -> "hex(salt):hex(hash)"
    return doPwHash(ctx, pw, docBlock, exception)

  ctx.registerFn passwordVerify(pw: string, stored: string):
    ## password.verify(pw, stored) -> bool
    return doPwVerify(ctx, pw, stored, docBlock, exception)

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
