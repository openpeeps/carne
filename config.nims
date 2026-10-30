# Carne build config: threads always on (per-worker runtimes for
# http.serve workers; single-threaded scripts are unaffected).
switch("threads", "on")
