---
name: dev-rust-code-create
description: "Write, extend, build, test, debug, and optimize Rust code and Cargo projects (Cargo.toml, workspaces, features, profiles, build.rs) against the installed toolchain, the project's MSRV/edition, and the crate versions in Cargo.lock. Use when asked to write Rust, scaffold or fix a Rust crate or workspace, fix rustc/borrow-checker/trait-bound/clippy errors, design error types (thiserror/anyhow), write async/Tokio services, threads/atomics/lock-free code, unsafe or FFI (bindgen, cbindgen, extern \"C\"), Linux systems or networking code (sockets, epoll/io_uring, signals, processes), add tests/proptest/fuzzing/Miri/criterion benchmarks, or profile and speed up Rust (SIMD, allocation, cache layout). For reviewing Rust code use dev-rust-code-review; for edition/toolchain/major-dependency upgrades use dev-rust-version-migrate; for COSMIC/libcosmic apps use dev-cosmic-app-create."
---

# Rust development

Rust's compiler catches most mistakes, so the failure modes for agents are different from
C/Zig: APIs newer than the project's MSRV, edition-2024 syntax in a 2021 crate, crate APIs
recalled from the wrong major version, `unwrap()` on untrusted input, `clone()`/`Rc<RefCell>`
to silence the borrow checker, blocking inside async, and unjustified `unsafe`. Model memory
is thin after Rust ~1.88 (mid-2025); the installed release notes fill the gap.

## Ground rules

- **Toolchain first.** Run `scripts/rust-env.sh <project>` before writing code: rustc version,
  pins, MSRV (`rust-version`), edition, installed tools. Exit 3 = pinned toolchain missing,
  overridden by `RUSTUP_TOOLCHAIN`, or rustc older than MSRV → tell the user and ask which to
  target; do not install toolchains or bump MSRV/edition silently.
- **Verify, don't recall.** For std APIs you have not verified this session:
  `scripts/api-find.sh <name>` (shows `#[stable(since)]` = required MSRV). For dependencies:
  `scripts/api-find.sh -c <crate> <name>` reads the source at the Cargo.lock version. Unsure
  when something stabilized: `scripts/releases.sh -g <name>`.
- Source-of-truth order, online docs, community skill packs, and version facts:
  [sources](references/sources.md).
- Match the code base: edition, MSRV, error style (thiserror/anyhow/custom), async runtime,
  module layout, `rustfmt.toml`/`clippy.toml`/`[lints]`. No new dependencies, features, or
  `unsafe` without asking (unless the user asked for that).
- No `unwrap()`/`expect()` on fallible runtime input in non-test code; no `unsafe` without a
  `// SAFETY:` comment; no blocking calls inside `async fn`; no `#[allow]` without a reason
  (`#[expect(lint, reason = "…")]`).

## Workflow

1. **Classify the task** and load only the matching references:

   ```sadkitti
   REFERENCE "references/sources.md"
   IF writing or changing Rust source (types, traits, generics, lifetimes, patterns, iterators, macros)
     REFERENCE "references/language.md"
   IF task defines or handles errors, Result/Option plumbing, panics, or exit codes
     REFERENCE "references/errors.md"
   IF task touches Cargo.toml, workspaces, features, profiles, build.rs, cross-compilation, dependencies
     REFERENCE "references/cargo.md"
   IF task uses async/await, Tokio, futures, channels, axum/reqwest/tonic/hyper, timeouts, shutdown
     REFERENCE "references/async.md"
   IF task uses threads, rayon, locks, atomics, lock-free structures, Send/Sync
     REFERENCE "references/concurrency.md"
   IF task contains unsafe, raw pointers, MaybeUninit, transmute, FFI, bindgen/cbindgen, extern "C", asm!, target_feature
     REFERENCE "references/unsafe-ffi.md"
   IF task does Linux syscalls, files, sockets, epoll/io_uring, processes, signals, daemons, privileges
     REFERENCE "references/systems.md"
   IF task is about speed, memory use, benchmarks, profiling, SIMD, allocators, release profiles
     REFERENCE "references/performance.md"
   IF task adds tests, proptest, fuzzing, Miri, sanitizers, coverage, or is a failing test, panic, hang, or compile error
     REFERENCE "references/testing.md"
   IF project edition < 2024, or task moves to a newer edition/toolchain/major dependency version
     REFERENCE "../dev-rust-version-migrate/SKILL.md"
   ```

2. **Check the toolchain** (read-only): `scripts/rust-env.sh [project]`. No Rust installed →
   tell the user (rustup: <https://rustup.rs>, or their package manager / `mise use rust`);
   don't install without approval. Missing components (`rust-src`, `clippy`, `miri`) → ask.

3. **Discover before writing.** Read the surrounding module, its tests, and `Cargo.toml`
   features. Check each std/crate API you plan to use with `api-find.sh`; confirm its
   `since` ≤ MSRV and that the needed crate feature is enabled. New projects: `cargo new`
   (`--lib`/`--bin`) instead of hand-writing manifests.

4. **Design types first.** Data types, error enums, trait boundaries, and public signatures
   before bodies: enums for states, newtypes for IDs/units, borrowed parameters, owned
   returns, explicit ownership of resources, `Send + 'static` where tasks/threads need it.

5. **Implement incrementally.** `cargo check` (or `scripts/check.sh -C -T`) after each step.
   Read the *first* error fully (`rustc --explain E0xxx`); fix ownership errors by changing
   the data flow, not by adding `clone()`/`'static`/`Rc<RefCell>` until it compiles.

6. **Test.** Unit tests for new logic next to the code; integration tests for public API;
   doctests on public items; property tests for parsers/encoders; fuzz targets for untrusted
   input parsers; `cargo +nightly miri test` for new `unsafe`; benchmarks before and after
   any optimization.

7. **Verify** before reporting done: `scripts/check.sh [-W] [project|file.rs] [-- --all-features]`
   → fmt, clippy (all targets), tests (+ doctests); add `-D` for public docs, `-m` for Miri on
   unsafe code, `-M` to build with the MSRV toolchain if installed. Report the stages that
   ran and their results; if a stage could not run (no toolchain/component), say so and list
   the APIs you verified with `api-find.sh` instead.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/rust-env.sh [-f field] [dir]` | toolchain, components, cargo subcommands, pins, MSRV, edition; exit 3 on mismatch |
| `scripts/api-find.sh [-c crate] [-p dir] [-d] [-b] [-a] [-n max] <regex> [path]` | pub declarations in std (rust-src) or a locked dependency, with `#[stable(since)]` |
| `scripts/releases.sh [-l] [-s section] [-g regex] [ver \| from..to]` | local release notes by version/range/grep |
| `scripts/check.sh [-F] [-C] [-T] [-W] [-D] [-m] [-M] [-N] [-r] [target] [-- cargo args]` | fmt → clippy → nextest/test (+doc, Miri, MSRV) gate with timeouts |

The scripts set `RUSTUP_AUTO_INSTALL=0` (never download toolchains) and honor `RUSTUP_TOOLCHAIN`.

## Done checklist

- [ ] Code targets the project's edition and MSRV; every new std API's `since` ≤ MSRV;
      every crate API checked at the locked version with the right features.
- [ ] `cargo fmt` clean; clippy clean on all targets (no new `#[allow]` without reason).
- [ ] Tests pass, including doctests; new logic has tests; error paths are tested.
- [ ] No `unwrap`/`expect`/indexing panics on untrusted input; errors carry context.
- [ ] Every `unsafe` block has a SAFETY comment and Miri ran (or the reason it couldn't).
- [ ] No blocking in async, no locks across `.await`, bounded channels/concurrency, timeouts.
- [ ] Performance changes come with before/after numbers from the same benchmark.
- [ ] New dependencies, features, or MSRV changes were approved and are in `Cargo.toml`.
