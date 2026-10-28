const env = require("std/env");
const fs = require("std/fs");

console.log("cwd: " + env.cwd());
console.log("args: " + env.args().join(","));

const path = env.args()[2] || "/tmp/carne_demo.txt";
fs.writeFile(path, "written by carne");
console.log("read back: " + fs.readFile(path));
console.log("exists: " + fs.exists(path));
