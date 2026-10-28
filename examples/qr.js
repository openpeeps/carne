const qr = require("std/qr");
const fs = require("std/fs");

// Terminal rendering for humans, SVG for everything else.
const q = qr.encode("https://example.com/menu");
console.log("size: " + q.size + "x" + q.size);
console.log(q.terminal);
fs.writeFile("/tmp/carne_demo_qr.svg", q.svg);
console.log("svg bytes: " + fs.readFile("/tmp/carne_demo_qr.svg").length);
fs.remove("/tmp/carne_demo_qr.svg");

// Higher correction survives scrambled printouts.
for (const level of ["L", "H"])
  console.log(level + ": version size " +
    qr.encode("backup code 7", {ecLevel: level}).size);
