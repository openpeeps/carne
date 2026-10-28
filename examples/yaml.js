const yaml = require("std/yaml");

const config = yaml.parse([
  "server:",
  "  host: localhost",
  "  port: 8080",
  "  tls: true",
  "features:",
  "  - logging",
  "  - metrics",
  "retries: 3",
  ""
].join("\n"));

console.log("host: " + config.server.host);
console.log("port: " + config.server.port);
console.log("features: " + config.features.join(", "));

const emitted = yaml.stringify({app: "carne", debug: false, tags: ["js", "nim"]});
console.log("---");
console.log(emitted);
console.log("roundtrip ok: " + (JSON.stringify(yaml.parse(emitted)).length > 0));
