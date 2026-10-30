# Carne http worker threads: cluster-style serve scaling.
#
# Each worker is a full runtime (own JS context in its own group, own
# powpow loop, own server) re-running the script source, so no JS value
# ever crosses a thread — the Node cluster model. Only Nim primitives
# (pipe fds, an adopt fd, atomics) are shared, under one lock.
#
# Ownership rule (Nim per-thread GC): the boot struct and its strings
# are manual memory (alloc0/dupCString). The worker copies them into
# GC strings on its own thread, then frees everything. Nothing GC'd
# crosses threads. Close/stop coordination is 4-byte pipe messages
# (a port int; 0 = stop everything), with closed/stopping flags so a
# worker that registers late still shuts down (no lost wakeups, no
# join hangs).

when not defined(windows):
  import std/[atomics, locks, tables]
  import std/posix

  import ../runtime

  type
    WorkerBootObj = object
      source, sourceURL, baseDir, host: cstring
      argv: cstringArray
      argc: int
      port: int
      listenFd: cint
      hasFd: bool
    WorkerBoot* = ptr WorkerBootObj

    WorkerCoord = object
      pipes: seq[cint]
      # Heap-stable Thread storage: pthread holds a pointer to the
      # Thread object itself (threadProcWrapDispatch reads dataFn/data
      # through it), so handles must NEVER move after createThread.
      # We store pointers (freed after join) and create/join in place.
      threads: seq[ptr Thread[WorkerBoot]]
      closed: bool

  var workerLock: Lock
  var workerLockState: Atomic[int]
  var workerRegs: Table[int, WorkerCoord]
  var workersStopping: Atomic[bool]

  var workerAdoptFd {.threadvar.}: cint
  var workerHasAdoptFd {.threadvar.}: bool

  proc ensureWorkerLock() =
    if workerLockState.load(moAcquire) != 2:
      if workerLockState.exchange(1, moAcquireRelease) == 0:
        initLock(workerLock)
        workerLockState.store(2, moRelease)
      else:
        while workerLockState.load(moAcquire) != 2:
          cpuRelax()

  proc dupCstr(s: string): cstring =
    ## Manual copy of a Nim string; worker-owned, dealloc'd by worker.
    if s.len == 0:
      result = cast[cstring](alloc(1))
      result[0] = '\0'
    else:
      result = cast[cstring](alloc(s.len + 1))
      copyMem(cast[pointer](result), unsafeAddr s[0], s.len)
      result[s.len] = '\0'

  proc freeBoot(arg: WorkerBoot) =
    dealloc(cast[pointer](arg.source))
    dealloc(cast[pointer](arg.sourceURL))
    dealloc(cast[pointer](arg.baseDir))
    dealloc(cast[pointer](arg.host))
    for i in 0 ..< arg.argc:
      dealloc(cast[pointer](arg.argv[i]))
    dealloc(arg.argv)
    dealloc(arg)

  proc httpWorkerMain(arg: WorkerBoot) {.thread.} =
    {.cast(gcsafe).}:
      # Safety by construction, not by checker: the boot struct is
      # manual memory (freed below), and everything GC'd past that is
      # allocated on this thread. Shared tables (installers, onTeardown)
      # are written pre-spawn and read-only after.
      let source = $arg.source
      let sourceURL = $arg.sourceURL
      let baseDir = $arg.baseDir
      var argv: seq[string] = @[]
      for i in 0 ..< arg.argc:
        argv.add($arg.argv[i])
      let port = arg.port
      workerAdoptFd = arg.listenFd
      workerHasAdoptFd = arg.hasFd
      freeBoot(arg)
      markHttpWorker()
      try:
        discard runCodeEx(source, sourceURL, argv, baseDir)
      except CatchableError as e:
        lockLog()
        try:
          stderr.writeLine("carne: http worker on port " & $port &
            " failed: " & e.msg)
        finally:
          unlockLog()

  proc makeBoot*(source, sourceURL, baseDir, host: string;
      argv: seq[string]; port: int; listenFd: cint;
      hasFd: bool): WorkerBoot =
    ## Manual-memory boot args for one worker (main thread).
    result = cast[WorkerBoot](alloc0(sizeof(WorkerBootObj)))
    result.source = dupCstr(source)
    result.sourceURL = dupCstr(sourceURL)
    result.baseDir = dupCstr(baseDir)
    result.host = dupCstr(host)
    result.argc = argv.len
    result.argv = cast[cstringArray](alloc((argv.len + 1) * sizeof(cstring)))
    for i, a in argv:
      result.argv[i] = dupCstr(a)
    result.argv[argv.len] = nil
    result.port = port
    result.listenFd = listenFd
    result.hasFd = hasFd

  proc spawnWorker*(boot: WorkerBoot; port: int) =
    ## Starts one worker thread, tracking its handle for teardown join.
    ## On spawn failure everything is freed and OSError raises.
    let th = cast[ptr Thread[WorkerBoot]](alloc0(sizeof(Thread[WorkerBoot])))
    try:
      createThread(th[], httpWorkerMain, boot)
    except CatchableError:
      dealloc(th)
      freeBoot(boot)
      raise
    ensureWorkerLock()
    withLock workerLock:
      workerRegs.withValue(port, c):
        c.threads.add(th)
      do:
        workerRegs[port] = WorkerCoord(threads: @[th])

  proc recordPipe*(port: int; writeFd: cint): bool =
    ## Records one worker's control-pipe write end. Returns true when
    ## the port was already closed/stopping: the caller must shut its
    ## server at once (missed-broadcast guard).
    ensureWorkerLock()
    withLock workerLock:
      workerRegs.withValue(port, c):
        c.pipes.add(writeFd)
        result = c.closed or workersStopping.load(moAcquire)
      do:
        workerRegs[port] = WorkerCoord(pipes: @[writeFd])
        result = workersStopping.load(moAcquire)

  proc markClosed*(port: int): seq[cint] =
    ## Marks a port closed, returning current pipe targets for broadcast.
    ensureWorkerLock()
    withLock workerLock:
      workerRegs.withValue(port, c):
        c.closed = true
        result = c.pipes

  proc stopAllWorkers*() =
    ## Main-thread teardown only (workers return at once): signals every
    ## worker to stop, then joins. Late registrants see workersStopping
    ## in recordPipe and shut themselves down, so join cannot hang.
    if inHttpWorker():
      return
    ensureWorkerLock()
    workersStopping.store(true, moRelease)
    var pipes: seq[cint] = @[]
    var threads: seq[ptr Thread[WorkerBoot]] = @[]
    withLock workerLock:
      for c in workerRegs.mvalues:
        c.closed = true
        for w in c.pipes:
          pipes.add(w)
        for t in c.threads:
          threads.add(t)
      workerRegs.clear()
    var stop: array[4, byte]
    for w in pipes:
      discard posix.write(w, addr stop[0], 4)
      discard posix.close(w)
    for i in 0 ..< threads.len:
      joinThread(threads[i][])
      dealloc(threads[i])
    # Quiescent again: every tracked worker is dead, so no late
    # registrant can exist. Without this reset, the next runCodeEx in
    # this process would see stopping and shut its own servers at once.
    workersStopping.store(false, moRelease)

  proc readWorkerAdoptFd*(): tuple[fd: cint, has: bool] =
    (workerAdoptFd, workerHasAdoptFd)
