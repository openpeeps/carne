---
title: Crypto
description: "Hashing, AEAD sealing, signatures, passwords."
keywords: ['carne', 'javascript', 'std', 'crypto', 'hash', 'signatures']
---

# Crypto

hashing, AEAD sealing, signatures, passwords

```js
const crypto = require("std/crypto");
console.log(crypto.hash.sha256hex("abc")); // "ba7816bf8f01cfea..."

const stored = crypto.password.hash("s3cret");      // argon2id "salt:hash"
console.log(crypto.password.verify("s3cret", stored)); // true

const keys = crypto.sign.keypair(); // {publicKey, secretKey} hex (ed25519)
const sig = crypto.sign.sign(keys.secretKey, "msg");
console.log(crypto.sign.verify(keys.publicKey, "msg", sig)); // true

const keyHex = "00".repeat(32); // 32-byte key as hex
const env = crypto.aead.seal("secret", keyHex); // {nonce, mac, cipher} hex
console.log(crypto.aead.open(env, keyHex));     // "secret" (throws on MAC failure)
```

All binary values cross the boundary as lowercase hex strings. `open`
throws on MAC failure; `verify` returns `false` on mismatch instead.
X25519/RSA/ECDSA and AES modes are deferred.


## hash.sha256hex

`hash.sha256hex(text) -> hex digest`

```js
const crypto = require("std/crypto");
crypto.hash.sha256hex("example");
```

## hash.sha384hex

`hash.sha384hex(text) -> hex digest`

```js
const crypto = require("std/crypto");
crypto.hash.sha384hex("example");
```

## hash.sha512hex

`hash.sha512hex(text) -> hex digest`

```js
const crypto = require("std/crypto");
crypto.hash.sha512hex("example");
```

## hash.blake2bhex

`hash.blake2bhex(text[, size]) -> hex digest (size 1..64, default 32)`

```js
const crypto = require("std/crypto");
crypto.hash.blake2bhex("example", 20);
```

## hash.hmacSha256hex

`hash.hmacSha256hex(keyHex, text) -> hex mac`

```js
const crypto = require("std/crypto");
crypto.hash.hmacSha256hex("example", "example");
```

## aead.seal

`aead.seal(text, keyHex) -> {nonce, mac, cipher}`

```js
const crypto = require("std/crypto");
crypto.aead.seal("example", "example");
```

## aead.open

`aead.open({nonce, mac, cipher}, keyHex) -> text`

```js
const crypto = require("std/crypto");
crypto.aead.open({}, "example");
```

## sign.keypair

`sign.keypair() -> {publicKey, secretKey} hex`

```js
const crypto = require("std/crypto");
crypto.sign.keypair();
```

## sign.keypairFromSeed

`sign.keypairFromSeed(seedHex) -> {publicKey, secretKey} hex`

```js
const crypto = require("std/crypto");
crypto.sign.keypairFromSeed("example");
```

## sign.sign

`sign.sign(secretHex, text) -> hex signature`

```js
const crypto = require("std/crypto");
crypto.sign.sign("example", "example");
```

## sign.verify

`sign.verify(publicHex, text, sigHex) -> bool`

```js
const crypto = require("std/crypto");
crypto.sign.verify("example", "example", "example");
```

## password.hash

`password.hash(pw) -> "hex(salt):hex(hash)"`

```js
const crypto = require("std/crypto");
crypto.password.hash("example");
```

## password.verify

`password.verify(pw, stored) -> bool`

```js
const crypto = require("std/crypto");
crypto.password.verify("example", "example");
```
