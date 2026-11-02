---
name: dev-c3-code-create
description: "Write, extend, build, test, and debug code in the C3 programming language (c3-lang.org, compiler c3c, 0.7.x–0.8.x) against the installed compiler and standard library. Use when asked to write C3, create or fix a C3 project (project.json, c3c build/test/run, .c3l libraries, vendor-fetch), use the C3 stdlib (allocators, mem/tmem/@pool, String/DString, List/HashMap, io/file/path, json, process, time), handle Optionals/excuses/defer/contracts, write generics/macros/compile-time code, do systems work in C3 (sockets, poll/epoll, threads, channels, atomics, SIMD vectors, libc/syscalls, benchmarks), bind C libraries, or fix C3 compile errors. Not for C3.ai. For porting old C3 code use dev-c3-version-migrate; for reviews use dev-c3-code-review."
---

# C3 development

C3 is pre-1.0 and renames syntax and stdlib APIs in nearly every release (0.7.0 and 0.8.0 were
large breaks; 0.8.4 renamed keywords again). Model memory of C3 is mostly 0.5/0.6 syntax
(`def`, `distinct`, `int!`, `fault Foo {}`, `$typeof`, `int.sizeof`, `usz` sizes) that no longer
compiles. Every API must be checked against the installed compiler's stdlib.

## Ground rules

- **Version first.** Run `scripts/c3-env.sh <project>`; target the installed c3c's release
  (x.y.z — C3 breaks APIs in patch releases). If CI pins another version (exit 3), ask which
  to target before writing code.
- **Verify, don't recall.** Before using a stdlib function/type you haven't verified this
  session: `scripts/std-find.sh <name> [path-filter]` (`-d` contracts, `-b` body, `-k type`).
  Language rules: `scripts/docs.sh -s/-p` — but the website tracks master and has known stale
  pages (see [sources](references/sources.md)); stdlib source and compiler tests win.
- Write idiomatic 0.8 C3: `excuse`/`constset`/`attrmacro` keywords on ≥0.8.4 (old spellings
  only if the project must build on ≤0.8.3), signed `sz` sizes, explicit allocators
  ("allocator first"), `@pool` for temporaries, Optionals + `!` for errors, contracts for
  preconditions, `@feat` for platform code.
- Match the project: its module layout, allocator conventions, brace style (stdlib: Allman,
  tabs). No new `.c3l` dependencies or `vendor-fetch` without asking.
- Keep safe builds the default (`-O0`/`-O1`); never "fix" crashes with `!!`, `(void)` discards,
  `@noinit`, or `--test-noleak`.

## Workflow

1. **Load references for the task:**

   ```sadkitti
   REFERENCE "references/sources.md"
   IF writing or changing C3 code (syntax, types, conversions, control flow, enums, structs)
     REFERENCE "references/language.md"
   IF code returns or handles errors, uses defer, or adds contracts/asserts
     REFERENCE "references/errors.md"
   IF code allocates, uses temp memory, containers' allocators, or custom allocators
     REFERENCE "references/allocators.md"
   IF code uses strings, collections, files/streams/paths, processes, env, time, JSON/encodings, sorting/hashing
     REFERENCE "references/stdlib.md"
   IF code does networking, poll/epoll, threads/pools/channels, atomics, SIMD, syscalls, or performance work
     REFERENCE "references/systems.md"
   IF code uses generics, macros, $if/$foreach, reflection, any/interfaces, or operator overloading
     REFERENCE "references/generics.md"
   IF task touches project.json, c3c commands/flags, libraries, vendor-fetch, cross-compiling
     REFERENCE "references/build.md"
   IF task binds or calls C libraries, exports to C, or compiles C sources
     REFERENCE "references/c-interop.md"
   IF task adds tests/benchmarks, or is a compile error, panic, leak, or crash
     REFERENCE "references/testing.md"
   IF code or project targets c3c < 0.8.5 or contains pre-0.8 syntax
     REFERENCE "../dev-c3-version-migrate/SKILL.md"
   ```

2. **Check the toolchain** (read-only): `scripts/c3-env.sh [dir]` — c3c path/version, stdlib
   dir, project.json summary, CI pin. No c3c → tell the user (prebuilt binaries:
   <https://github.com/c3lang/c3c/releases>, e.g. `c3-linux.tar.gz`); don't install without approval.

3. **Discover before writing**: look up each stdlib API with `std-find.sh`; copy patterns from
   the stdlib, its unit tests, and `resources/examples` of the same tag. New projects:
   `c3c init <name>` rather than hand-written project.json.

4. **Design**: types and `excuse`s first; allocator parameters and ownership in `<* *>` docs;
   Optionals for runtime failure, `@require` for caller contracts; `@pool` boundaries per
   request/frame/loop iteration.

5. **Implement incrementally**, type-checking often (`scripts/check.sh -T` or
   `c3c compile-only --no-obj file.c3`). Fix the first error first.

6. **Test**: `@test` functions next to the code (leak-checked automatically), cover every
   excuse path with `test::@error`, add `@benchmark`s for hot paths.

7. **Verify** before reporting: `scripts/check.sh [project|files] [-S] [-- extra c3c args]` —
   build + tests (`-S` turns deprecations into errors). Report what ran; if no compiler was
   available, say the code is unverified and list the APIs checked against stdlib source.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/c3-env.sh [-f field] [dir]` | toolchain, stdlib dir, project.json, CI-pinned version (exit 3 on mismatch) |
| `scripts/std-find.sh [-d] [-b] [-a] [-k kind] <regex> [path]` | find stdlib declarations (+ module, contracts, bodies) |
| `scripts/docs.sh -s regex \| -p page \| -l \| -r version` | search/print official docs (cached clone) and per-version release notes |
| `scripts/check.sh [-T] [-S] [-O lvl] [-n target] [paths] [-- args]` | build/type-check + tests with timeouts |

All honor `C3C=/path/to/c3c` (and `C3C_LIB`) for side-by-side compilers.

## Done checklist

- [ ] Targets the installed/pinned c3c release; every stdlib API verified this session.
- [ ] Builds in a safe build with no deprecation warnings; `c3c test` passes with leak checking.
- [ ] Every heap allocation has an owner and a `defer`/`defer (catch)`/free path; temp memory
      never escapes its `@pool`; raw threads use `@pool_init`.
- [ ] No `!!`, `(void)` discards, or `@noinit` on paths that can fail with real input.
- [ ] Sizes/indices are `sz`; explicit casts at signed/unsigned boundaries; ZString for C.
- [ ] Platform code gated with `@feat`; `.gitignore` covers `build/`/`out/`.
