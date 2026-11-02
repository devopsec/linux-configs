# C3 sources of truth

C3 (c3-lang.org, compiler `c3c`) is pre-1.0 and renames or removes syntax and stdlib APIs in
almost every release, including patch releases. Training data is mostly 0.5–0.6 era code
(`def`, `distinct`, `int!`, `fault Foo {}`, `$typeof`, `int.sizeof`, `usz` everywhere) that does
not compile on 0.8.x. Check every API against the compiler in use.

## Order of trust

1. **Installed stdlib source** — `scripts/std-find.sh <name> [path-filter]` (stdlib located like
   c3c does: `$C3C_LIB`, then `../lib/std` next to the binary). Signatures, `<* *>` contracts,
   `@deprecated`, `@builtin` (call without module prefix) are authoritative.
2. **Compiler test suite and examples** for the same tag
   (<https://github.com/c3lang/c3c/tree/v0.8.5_1/test>, `/resources/examples`): real, compiling
   usage of every feature; `test/test_suite/**` files mark expected errors with `// #error:`.
3. **Release notes** — `scripts/docs.sh -r 0.8.5` (every rename/removal is listed per version;
   0.x.0 releases collect the breaking changes).
4. **Language docs** — `scripts/docs.sh -s <regex>` / `-p <page>` (sources of
   <https://c3-lang.org/>). They track compiler **master**, so they can describe features newer
   than the installed compiler, and some pages are stale. Known drift as of 0.8.5:
   - `alias.md` says literals convert to `typedef` types — since 0.7.10/0.8.0 only with
     `@constinit` (`types.md` is correct).
   - `contracts.md` / `generics.md` use `$assignable` — removed in 0.8.0; use `$defined(T x = expr)`.
   - `conversion.md` describes unsigned promotion and implicit signed↔unsigned conversion — 0.8.0
     promotes small unsigned to `int` and **removed** implicit signed↔unsigned conversion.
   - `debugging.md` shows `@assert_always` — the 0.8.5 builtin is `always_assert(cond, fmt, ...)`.
   - `project-config.md` lists `depends-on`, `env`, `env-override`, `${VAR}` expansion and the
     `source-lib` target type — **not in 0.8.5** (master only). Authoritative key list:
     `c3c --list-project-properties`.
   - `anyinterfaces.md` example uses `string::printf(..., allocator:)` — use
     `string::format(allocator, fmt, ...)`.
5. **Upstream repos (GitHub)**: compiler + stdlib <https://github.com/c3lang/c3c> (tags
   `v0.8.5_1`, nightly `latest-prerelease-tag`), docs <https://github.com/c3lang/c3-web>, bindings
   <https://github.com/c3lang/vendor> (`c3c vendor-fetch <lib>`), spec
   <https://github.com/c3lang/c3-spec>, editor/LSP plugins <https://github.com/c3lang/editor-plugins>.
6. **Community** (not endorsed; check the C3 version each targets): c3-showcase list
   <https://github.com/c3lang/c3-showcase> (libraries, `c3fmt` formatter, `c3vm` version manager),
   learn-c3 <https://learn-c3.org>, Ebn's tutorials. There was no maintained agent skill for C3
   as of 2026-11; "C3" search hits for C3.ai are unrelated.

## Versions (as of 2026-11-01)

| Version | Date | Headline |
|---|---|---|
| 0.7.0 | 2025-03 | `def`→`alias`, `distinct`→`typedef`, `int!`→`int?`, `faultdef`, `anyfault`→`fault`, generics `Foo{int}` |
| 0.7.4–0.7.11 | 2025-08 – 2026-04 | const enums → `constdef`, `@constinit`, `~` creates faults (`io::EOF~`), declaration-level generics `<Type>`, `Process` |
| 0.8.0 | 2026-05 | signed sizes (`isz`→`sz`, no implicit signed↔unsigned), `Type::size` reflection, `$Typeof`, `.description`, enums lose `+`/`-`, JSON/Path API changes |
| 0.8.3 | 2026-08 | `@feat`/`$feat` replace top-level `@if`/`$feature` |
| 0.8.4 | 2026-09 | "last renaming": `excuse`/`attrmacro`/`constset` (old `faultdef`/`attrdef`/`constdef` still accepted in 0.8.x) |
| 0.8.5 | 2026-10 | current stable (`0.8.5_1` patch); stdlib uses `excuse`/`constset`; new `std::gfx`, C backend (experimental) |
| 0.9.0 | planned | syntax freeze; new keyword set becomes standard |

Port across versions with the `dev-c3-version-migrate` skill.

## Quick lookups

```bash
scripts/c3-env.sh .                          # compiler, stdlib dir, project.json, CI pin
scripts/std-find.sh 'List\.push' collections # method signature
scripts/std-find.sh -d '@pool' core/mem      # with <* *> contract
scripts/std-find.sh -k type 'Allocator'      # type declarations only
scripts/std-find.sh -a 'FILE_NOT_FOUND' io   # any line (faults live in excuse lists)
scripts/docs.sh -p c-to-c3                   # the C → C3 guide
scripts/docs.sh -s 'nextcase'                # search docs
scripts/docs.sh -r 0.8.0                     # what changed in 0.8.0
c3c --list-project-properties                # project.json keys for THIS compiler
c3c --list-attributes / --list-builtins / --list-keywords / --list-type-properties / --list-precedence / --list-targets
```
