const http = require("std/http");

(async () => {
  // One call: handler, port, done. Handlers answer with a string
  // (200 text/plain) or a {status, headers, body} object.
  const srv = http.serve(3000, req => {
    if (req.path === "/hello")
      return {body: "hi " + req.query.split("=").pop()};
    if (req.path === "/echo")
      return {status: 201, body: req.method + ":" + req.body};
    return {status: 404, body: "nope"};
  });
  console.log("serving on " + srv.host + ":" + srv.port);

  // Client calls are Promises on the shared loop: concurrent fetches
  // multiplex with timers and server sockets, no threads.
  const [hello, echo, missing] = await Promise.all([
    http.get("http://127.0.0.1:3000/hello?name=ada"),
    http.post("http://127.0.0.1:3000/echo", "ping"),
    http.fetch("http://127.0.0.1:3000/nowhere")
  ]);
  console.log(hello.status + " " + hello.body);
  console.log(echo.status + " " + echo.body);
  console.log(missing.status + " " + missing.body);

  http.close(srv.port);
  console.log("closed");
})();
