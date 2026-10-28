const bson = require("std/bson");

const doc = {
  hello: "world",
  n: 42,
  price: 9.99,
  active: true,
  nothing: null,
  tags: ["a", "b"],
  nested: {x: 1}
};

const encoded = bson.stringify(doc);
console.log("encoded length: " + encoded.length);

const decoded = bson.parse(encoded);
console.log("hello: " + decoded.hello);
console.log("nested.x: " + decoded.nested.x);
console.log("roundtrip ok: " + (JSON.stringify(decoded) === JSON.stringify(doc)));
