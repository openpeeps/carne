const qr = require("std/qr");
const os = require("std/os");

// Terminal rendering for humans, SVG for everything else.
const q = qr.encode("https://example.com/menu");
console.log("size: " + q.size + "x" + q.size);
console.log(q.terminal);
os.writeFile("/tmp/carne_demo_qr.svg", q.svg);
console.log("svg bytes: " + os.readFile("/tmp/carne_demo_qr.svg").length);
os.remove("/tmp/carne_demo_qr.svg");

// Higher correction survives scrambled printouts.
for (const level of ["L", "H"])
  console.log(level + ": version size " +
    qr.encode("backup code 7", {ecLevel: level}).size);
