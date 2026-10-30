// Carne std/mimetype: MIME type lookup via mimedb.
// Run: carne run examples/mimetype.js
const mimetype = require("std/mimetype");

console.log(mimetype.lookup("html")); // "text/html"
console.log(mimetype.lookup(".PNG")); // "image/png"
console.log(mimetype.lookup("nope")); // null

const info = mimetype.info("text/html");
console.log(info.source); // "iana"
console.log(info.compressible); // true
console.log(info.extensions.join(",")); // "html,htm,shtml"

console.log(mimetype.isExtension("zip")); // true
console.log(mimetype.has("audio/mp4")); // true
