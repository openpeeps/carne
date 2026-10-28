const path = require("std/path");

// Local paths.
console.log(JSON.stringify(path.parse("/usr/local/bin/carne")));
console.log(JSON.stringify(path.parse("relative/file.txt")));
console.log(JSON.stringify(path.parse("C:\\Users\\ada\\code")));

// URLs of every kind.
for (const u of ["https://example.com/a/b?x=1&y=2#top",
    "sftp://deploy@host.local:2222/srv/app",
    "git@github.com:openpeeps/carne.git",
    "mailto:ada@example.com"]) {
  const p = path.parse(u);
  console.log(p.kind + " :: " + (p.host || p.path || p.segments.join("/")));
}
