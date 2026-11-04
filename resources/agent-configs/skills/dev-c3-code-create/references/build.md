# Building: c3c CLI, project.json, libraries, cross-compilation (0.8.5)

Authoritative for your compiler: `c3c --help`, `c3c --list-project-properties`,
`c3c --list-targets`. Usage form: `c3c [options] <command> [args]` (options may also follow).

## Commands

| Command | Use |
|---|---|
| `c3c init <name> [--template exe\|static-lib\|dynamic-lib]` | new project (`src/main.c3`, `project.json`, `lib/`, `test/`, `build/`) |
| `c3c init-lib <name>` | new `.c3l` library skeleton |
| `c3c build [target]` / `run [target] [-- args]` / `clean-run` | project build / run (searches upward for project.json) |
| `c3c test [target]` / `benchmark [target]` | run `@test` / `@benchmark` functions |
| `c3c compile a.c3 b.c3` / `compile-run … [-- args]` | no project; output named after the file with `main` |
| `c3c compile-only --no-obj f.c3` | type-check only, no artifacts |
| `c3c compile-test f.c3` / `compile-benchmark f.c3` | tests/benchmarks without a project |
| `c3c static-lib f.c3` / `dynamic-lib f.c3` | libraries without a project |
| `c3c vendor-fetch <lib>…` | download from github.com/c3lang/vendor into `lib/` + add to `dependencies` (no args: list) |
| `c3c fetch-sdk windows\|macos\|android` | SDKs for cross-compiling |
| `c3c project view` / `project add-target <name> <type>` / `project fetch` | inspect/edit project.json |
| `c3c docgen [paths]` | HTML docs from `<* *>` comments |

## Key options

| Option | Effect |
|---|---|
| `-O0` (default) / `-O1` | **safe**: bounds/null/contract checks, backtraces (`-O1` optimizes) |
| `-O2` `-O3` | **unsafe**: checks off, contracts assumed; `-O3` single-module |
| `-O4` `-O5` | + relaxed/fast math, no panic messages (`-O5` no backtrace) |
| `-Os` `-Oz` | unsafe, size-optimized, no debug info |
| `--safe=yes\|no`, `--panic-msg=…`, `--show-backtrace=…` | override pieces of the above |
| `-g` / `-g0` | debug info on/off |
| `-D NAME` | enable feature flag (`$feat(NAME)`, `@feat(NAME)`) |
| `--target linux-aarch64` | cross-compile (`--list-targets`) |
| `--linux-libc=musl` | static musl Linux binaries |
| `--sanitize=address\|memory\|thread` | sanitizers |
| `--trap-on-wrap` | panic on integer wrap (testing) |
| `--warn-deprecation=error`, `--warn-unusedlocal=yes`, `--warn-unusedparam=yes` | stricter checks |
| `--lib <name>` `--libdir <dir>` | use `.c3l` libraries without a project |
| `-l foo` `-L dir` | link C libraries |
| `--trust=include\|full` | allow `$include` / `$exec` + project `exec` (code execution at build time) |
| `--test-filter name`, `--test-noleak`, `--test-show-output`, `--test-quiet` | test runner |
| `--emit-llvm`, `--emit-asm`, `--keep-obj`, `--print-large-functions` | inspection |
| `--x86cpu=… --x86vec=… --cpu-flags=+avx2` | codegen level |

## project.json (JSON5 comments allowed; also `project.json5`)

```json5
{
  "langrev": "1",
  "authors": ["Name <mail@example.com>"],
  "version": "0.1.0",
  "sources": ["src/**"],
  "test-sources": ["test/**"],
  "dependency-search-paths": ["lib"],
  "dependencies": ["sqlite3"],              // .c3l libraries (vendor-fetch adds here)
  "linked-libraries": ["m"],                // C libraries (-l)
  "linker-search-paths": [],
  "c-sources": ["csrc/**"], "c-include-dirs": ["csrc/include"], "cflags": "-O2",
  "features": ["USE_EPOLL"],
  "warnings": ["no-unused"],
  "build-dir": "build", "output": "build",
  "opt": "O0",                              // per-target override below
  "safe": true,
  "targets": {
    "server":       { "type": "executable" },
    "server-rel":   { "type": "executable", "opt": "O2", "name": "server" },
    "server-musl":  { "type": "executable", "target": "linux-x64", "linux-libc": "musl" },
    "unit":         { "type": "test" },
    "corelib":      { "type": "static-lib", "sources-override": ["src/core/**"] }
  }
}
```

- Target types (0.8.5): `executable`, `static-lib`, `dynamic-lib`, `benchmark`, `test`,
  `object-files`, `prepare`. Target keys override globals; `*-override` keys replace lists.
- Other useful keys: `cc`, `linker`, `link-args`, `exec`/`exec-override` (needs `--trust=full`),
  `script-dir`, `run-dir`, `no-entry`, `panicfn`, `testfn`, `strip-unused`, `single-module`,
  `x86cpu`, `x86vec`, `cpu-flags`, `reloc`, `sanitize`, `trap-on-wrap`, `stack-protector`,
  `function-sections`, `data-sections`, `use-stdlib`, `link-libc`, `memory-env`, `template`.
- **Not in 0.8.5** (docs mention them; master only): `depends-on`, `env`, `env-override`,
  `${VAR}` expansion, `source-lib` target, `compress`.
- Unknown keys are errors — check `c3c --list-project-properties` before adding one.

## Libraries (`.c3l`)

- A `.c3l` is a directory or zip with `manifest.json` (`provides`, `sources`, `targets` →
  per-platform `linked-libraries`, `link-args`, `dependencies`, `c-sources`), C3 sources or
  `.c3i` interface files, and per-target prebuilt libs.
- Use: put in `lib/` and add to `"dependencies"`, or `--libdir lib --lib name`.
- Official bindings: `c3c vendor-fetch raylib55 sqlite3 curl …` (repo pins: check the badge for
  the C3 version they target before relying on them).

## Cross-compilation

- `c3c build --target <os-arch>` uses LLVM + bundled linkers; Linux targets link against the
  host or musl libc (`--linux-libc`), Windows/macOS need `c3c fetch-sdk windows|macos` (or
  `--win-sdk`, `--macos-sdk`).
- Features (`LINUX`, `WIN32`, `POSIX`, …) follow the target, so `@feat` code switches automatically.

## Housekeeping

- `.gitignore`: `build/`, `out/` (template default), `*.o`.
- No official formatter: follow the surrounding style (stdlib: tabs, Allman). Community `c3fmt`
  exists — use only if the project already does.
- LSP / editor support: c3lang/editor-plugins (VS Code `c3`, tree-sitter-c3).
