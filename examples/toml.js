const toml = require("std/toml");

const cfg = toml.parse([
  'title = "carne demo"',
  'count = 3',
  'ratio = 0.5',
  'enabled = true',
  'started = 1979-05-27T07:32:00Z',
  '',
  '[database]',
  'host = "db.local"',
  'port = 5432',
  ''
].join("\n"));

console.log("title: " + cfg.title);
console.log("db: " + cfg.database.host + ":" + cfg.database.port);
console.log("started (as string): " + cfg.started);

const out = toml.stringify({app: {name: "carne", workers: 4}});
console.log("---");
console.log(out);
