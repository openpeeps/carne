const http = require("http");

// Hello-world server for bench/http-hello/run.sh (wrk, port 3000).
// Mirrors server.carne.js: every request answers 200 text/plain "hello world".
http.createServer((req, res) => {
  res.writeHead(200, {"Content-Type": "text/plain", "Content-Length": 11});
  res.end("hello world");
}).listen(3000, "127.0.0.1");
