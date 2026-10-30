const http = require("std/http");

// Hello-world server for bench/http-hello/run.sh (wrk, port 3000).
// Minimal handler: every request answers 200 text/plain "hello world".
http.serve(3000, req => "hello world");
