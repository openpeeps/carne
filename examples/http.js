const http = require("std/http");

// Long-lived server: no close, the run stays alive serving until Ctrl-C.
// Try: curl http://127.0.0.1:3000/hello?name=ada
const srv = http.serve(3000, req => {
  // console.log(req.method + " " + req.url);
  if (req.path === "/hello") {
    const name = (req.query.split("=").pop() || "stranger");
    return {body: "hi " + name};
  }
  if (req.path === "/echo")
    return {status: 201, body: req.method + ":" + req.body};
  return {status: 404, body: "nope"};
});

console.log("serving on " + srv.host + ":" + srv.port);
