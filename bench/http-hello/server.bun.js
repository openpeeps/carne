// Hello-world server for bench/http-hello/run.sh (wrk, port 3000).
// Mirrors server.carne.js: every request answers 200 text/plain "hello world".
Bun.serve({
  port: 3000,
  hostname: "127.0.0.1",
  fetch() {
    return new Response("hello world", {
      headers: {"Content-Type": "text/plain", "Content-Length": "11"}
    });
  }
});
