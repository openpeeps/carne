const dotenv = require("std/dotenv");
const env = require("std/env");
const os = require("std/os");

const parsed = dotenv.parse([
  "# demo env",
  "APP_NAME=carne",
  "APP_PORT=8080",
  'GREETING="hello $APP_NAME on $APP_PORT"',
  "RAW='no $expansion here'",
  "export SHARED=yes",
  ""
].join("\n"));

console.log("parsed GREETING: " + parsed.GREETING);
console.log("parsed RAW: " + parsed.RAW);

const tmp = "/tmp/carne_dotenv_demo";
os.writeFile(tmp, "CARNE_DEMO_LOADED=it-works\n");
dotenv.load(tmp);
console.log("loaded into env: " + env.getenv("CARNE_DEMO_LOADED"));
os.remove(tmp);
