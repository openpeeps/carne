const ws = require("std/ws");

// Long-lived echo server: no close, the run stays alive until Ctrl-C.
// Talk to it with examples/ws-client.js below.
const srv = ws.serve(8080, {
  onOpen: (conn) => console.log("open"),
  onMessage: (conn, msg) => {
    console.log("msg: " + msg.data);
    conn.send("echo:" + msg.data);
  },
  onClose: (conn, e) => console.log("close " + e.code)
});

console.log("serving ws on " + srv.host + ":" + srv.port);
