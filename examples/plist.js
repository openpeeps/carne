const plist = require("std/plist");

const doc = plist.parse(
  '<?xml version="1.0"?>' +
  '<plist version="1.0"><dict>' +
  '<key>CFBundleName</key><string>CarneDemo</string>' +
  '<key>CFBundleVersion</key><string>3</string>' +
  '<key>LSRequiresIPhoneOS</key><true/>' +
  '<key>URLs</key><array><string>https://a.example</string>' +
  '<string>https://b.example</string></array>' +
  '</dict></plist>');

console.log("name: " + doc.CFBundleName);
console.log("requires iOS: " + doc.LSRequiresIPhoneOS);
console.log("urls: " + doc.URLs.join(", "));

const back = plist.parse(plist.stringify({answer: 42, ok: true}));
console.log("roundtrip: " + JSON.stringify(back));
