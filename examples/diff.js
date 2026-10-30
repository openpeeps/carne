const diff = require("std/diff");
const os = require("std/os");

const before = ["line one", "line two", "line three", "line four"].join("\n") + "\n";
const after = ["line one", "LINE TWO", "line three", "line five"].join("\n") + "\n";

// Machine-readable form for tooling.
const d = diff.diff(before, after);
console.log("identical: " + d.identical +
  " (+" + d.stats.added + " -" + d.stats.removed + ")");
for (const h of d.hunks) {
  console.log(h.header);
  for (const l of h.lines)
    console.log("  " + l.kind + " :: " + l.text);
}

// Human-readable unified text, ready to store or send.
const patch = diff.unified(before, after);
console.log("--- patch ---");
console.log(patch);
os.writeFile("/tmp/carne_demo.patch", patch);
console.log("wrote " + os.readFile("/tmp/carne_demo.patch").length + " bytes");
os.remove("/tmp/carne_demo.patch");
