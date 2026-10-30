const env = require("std/env");
const os = require("std/os");

console.log("cwd: " + env.cwd());
console.log("args: " + env.args().join(","));

const path = env.args()[2] || "/tmp/carne_demo.txt";
os.writeFile(path, "written by carne");
console.log("read back: " + os.readFile(path));
console.log("exists: " + os.exists(path));
