# datpkgr integration — Phase 1 (built 2026-10-28)

## Decisions
- Manifest: npm-spec `package.json`, parsed with openparser/json
  (JsonNode is std/json's, re-exported). `name`+`version` required,
  npm new-package name rules, exact semver, legacy license object
  coerced, semver ranges via datpkgr `parseConstraint`, `npm:` aliases,
  git specs to `url`, `file:`/tarballs/compound ranges/dist-tags are
  manifest errors. `peerDependencies` carried, no solver.
- Registry: placeholder `carne/pkgs` URL const; git URL + develop work now.
- Scope: `carne pkg` CLI only; runtime `require("pkg/")` is Phase 2.

## Files
- `src/carne/pkg/pkgmanifest.nim`: parser, `findPackageJson`,
  `manifestMain`. Threads-free (imports resolver only, not operations).
- `src/carne/pkg/pkgman.nim`: `~/.carne` home, config, wrappers,
  `packageEntryPoint` (`main`, else index/src-index/name fallbacks),
  `resolvePkgImport`. Imports under `when isMainModule` in carne.nim
  so library use stays threads-free.
- `src/carne.nims`: `--threads:on`. `tests/config.nims`: same.
- `carne.nimble`: + `datpkgr >= 0.1.11`, `semver >= 1.2.3`.

## Verification
- 7 suites pass (`test_manifest` 17 tests, `test_pkgman` 5 tests).
- Manual: fresh-home list, develop/list/remove roundtrip via
  `CARNE_HOME`, run/timers/help regression intact.
