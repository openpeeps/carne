# Carne - a JavaScript runtime on JavaScriptCore (macOS + Linux).
#
# Library API: runCode / runFile from ./carne/runtime.
# CLI: `carne run <script.js> [args]`, --help, --version.

import ./carne/runtime
export runtime

when isMainModule:
  import std/[os, parseopt]

  import ./carne/cli
  import ./carne/std/all
  import ./carne/pkg/pkgman

  proc runScriptFile(filePath: string; extraArgs: seq[string]): int =
    ## Execute JS from a file
    try:
      let res = runFileEx(filePath, extraArgs)
      return res.code
    except CarneError as e:
      echo errPrefix() & " " & e.msg
      return 1
    except IOError as e:
      echo errPrefix() & " " & e.msg
      return 1

  proc printPkgHelp() =
    echo "usage: carne pkg <install|remove|update|list|develop|prune|refresh> [args]"
    echo ""
    echo "  install <spec> [--url=...]  " & grey("registry name, git URL, gh:user/repo alias, name#ref, or name + source URL")
    echo "  remove <name> [version]     " & grey("uninstall one version, or all versions")
    echo "  update [name]               " & grey("update one package, or all")
    echo "  list                        " & grey("list installed packages")
    echo "  develop <path>              " & grey("editable install from a local directory")
    echo "  prune                       " & grey("remove orphaned packages")
    echo "  refresh                     " & grey("re-download registry data")

  proc runPkg(args: seq[string], pkgUrl: string): int =
    ## Package management on the ~/.carne home (CARNE_HOME overrides).
    if args.len == 0:
      printPkgHelp()
      return 1
    let cfg = newCarnePkgConfig()
    case args[0]
    of "install":
      if args.len < 2:
        echo errPrefix() & " package name or URL is required"
        printPkgHelp()
        return 1
      if args.len > 2:
        echo errPrefix() & " only one package allowed"
        return 1
      try:
        if cfg.pkgInstall(args[1], url = pkgUrl):
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "remove", "uninstall":
      if args.len < 2:
        echo errPrefix() & " package name is required"
        printPkgHelp()
        return 1
      if args.len > 3:
        echo errPrefix() & " usage: carne pkg remove <name> [version]"
        return 1
      let version = if args.len > 2: args[2] else: ""
      try:
        if cfg.pkgRemove(args[1], version):
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "update":
      if args.len > 2:
        echo errPrefix() & " usage: carne pkg update [name]"
        return 1
      let name = if args.len > 1: args[1] else: ""
      try:
        if cfg.pkgUpdate(name):
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "list":
      try:
        cfg.pkgList()
        return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "develop":
      if args.len != 2:
        echo errPrefix() & " directory is required (usage: carne pkg develop <path>)"
        return 1
      try:
        if cfg.pkgDevelop(args[1]):
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "prune":
      try:
        cfg.pkgPrune()
        return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "refresh":
      try:
        if cfg.refreshAllSources():
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    else:
      echo errPrefix() & " unknown pkg command `" & args[0] & "`"
      printPkgHelp()
      return 1

  proc main(): int =
    var command = ""
    var positionals: seq[string] = @[]
    var showHelp = false
    var showVersion = false
    var pkgUrl = ""
    var p = initOptParser(commandLineParams())
    for kind, key, val in p.getopt():
      case kind
      of cmdArgument:
        if command == "":
          command = key
        else:
          positionals.add(key)
      of cmdLongOption, cmdShortOption:
        case key
        of "help", "h":
          showHelp = true
        of "version":
          showVersion = true
        of "url":
          pkgUrl = val
        else:
          echo errPrefix() & " unknown option --" & key
          printHelp()
          return 1
      of cmdEnd:
        discard
    if showVersion:
      echo versionStr
      return 0
    if showHelp:
      printHelp()
      return 0
    if command == "":
      printHelp()
      return 0
    case command
    of "run":
      # run a .js script file
      if positionals.len == 0:
        echo errPrefix() & " script is required"
        printHelp()
        return 1
      let script = positionals[0]
      let extra = if positionals.len > 1: positionals[1 .. ^1] else: @[]
      return runScriptFile(script, extra)
    of "pkg":
      # package management on the ~/.carne home
      return runPkg(positionals, pkgUrl)
    else:
      # default command: a bare script path runs like `run <script>`
      if positionals.len >= 0 and fileExists(command):
        return runScriptFile(command, positionals)
      echo errPrefix() & " unknown command `" & command & "`"
      printHelp()
      return 1

  quit(main())
