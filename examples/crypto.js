const crypto = require("std/crypto");

// Hashing: one-shot digests as lowercase hex.
console.log("sha256: " + crypto.hash.sha256hex("abc"));
console.log("sha512 length: " + crypto.hash.sha512hex("abc").length);
console.log("blake2b-128: " + crypto.hash.blake2bhex("abc", 16));
console.log("hmac: " + crypto.hash.hmacSha256hex("6b6579",
  "The quick brown fox jumps over the lazy dog"));

// AEAD: seal with a random nonce, open with the envelope.
const key = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
const env = crypto.aead.seal("attack at dawn", key);
console.log("sealed: nonce=" + env.nonce.length / 2 + "B mac=" +
  env.mac.length / 2 + "B cipher=" + env.cipher.length / 2 + "B");
console.log("opened: " + crypto.aead.open(env, key));

// Tampering is detected.
const tampered = {nonce: env.nonce, mac: env.mac, cipher: "ff" + env.cipher.slice(2)};
try {
  crypto.aead.open(tampered, key);
} catch (e) {
  console.log("tamper rejected: " + e.message.split("\n")[0]);
}

// Signatures: deterministic from a seed, random otherwise.
const kp = crypto.sign.keypairFromSeed(key);
console.log("pub: " + kp.publicKey);
const sig = crypto.sign.sign(kp.secretKey, "transfer 100");
console.log("valid: " + crypto.sign.verify(kp.publicKey, "transfer 100", sig));
console.log("forged: " + crypto.sign.verify(kp.publicKey, "transfer 999", sig));

// Passwords: argon2id hash, constant-time verify.
const stored = crypto.password.hash("correct horse");
console.log("stored: " + stored.slice(0, 12) + "...");
console.log("login ok: " + crypto.password.verify("correct horse", stored));
console.log("login bad: " + crypto.password.verify("wrong horse", stored));
