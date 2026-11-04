---
name: dev-rust-code-review
description: "Review, audit, or assess Rust code, Cargo.toml, and Rust PRs/diffs for soundness (unsafe, FFI, Send/Sync), panics and error handling, ownership and resource leaks, async/Tokio and thread concurrency bugs, integer/casting issues, security of untrusted input (SQL, shell, paths, TLS, deserialization), API design, dependency/feature hygiene, MSRV/edition drift, tests, performance, and idiomatic style — and recommend clippy/[lints] policy. Use when asked to review/audit/check Rust code, look for UB/unsoundness/panics/deadlocks/leaks in Rust, assess whether Rust is idiomatic, or set up clippy lints. For writing or fixing code use dev-rust-code-create; for edition/toolchain upgrades use dev-rust-version-migrate."
---

# Rust code review

Find real defects first (unsoundness, reachable panics, swallowed errors, async/concurrency
bugs, injection), then design and style. The compiler already proved memory safety for safe
code — spend attention on `unsafe`, on logic, on what panics, and on what runs concurrently.
Every finding cites `file:line`, the failure scenario, and a concrete fix valid for the
project's MSRV and edition.

## Ground rules

- Establish the toolchain context first: `../dev-rust-code-create/scripts/rust-env.sh <project>`
  (edition, `rust-version`, pinned toolchain). Don't suggest APIs newer than the MSRV — check
  with `../dev-rust-code-create/scripts/api-find.sh` (`since`) and say when a fix needs an
  MSRV bump.
- Scripts and clippy produce **leads**; confirm each by reading the code. Drop false
  positives silently.
- Severity: **blocker** (unsound safe API / UB, panic or injection reachable from untrusted
  input, data loss, deadlock, secrets exposure), **major** (likely bug, swallowed errors,
  missing tests for risky logic, blocking in async, unbounded resources), **minor** (design,
  API ergonomics, performance, MSRV/edition drift), **nit** (style). Don't pad with nits.
- Verify std/crate claims (`api-find.sh`, `api-find.sh -c <crate>` at the locked version)
  before asserting that an API is misused or missing.
- Review the diff in context: read callers/callees of changed functions for ownership,
  error, cancellation, and locking contracts; read `Cargo.toml` changes and feature flags.
- Read-only: don't edit files unless the user asks for fixes.

## Workflow

1. **Scope**: files/diff to review (`git diff --name-only <base>...` for PRs), crate(s)
   touched, edition/MSRV, runtime (Tokio? threads?), presence of `unsafe`/FFI, and the
   project's lint policy (`[lints]`, `clippy.toml`, CI flags).

2. **Load references**:

   ```sadkitti
   REFERENCE "references/checklist.md"
   IF user asks about lint policy OR project has no [lints]/clippy config OR clippy leads are needed
     REFERENCE "references/lints.md"
   IF reviewed code uses unsafe, FFI, raw pointers, or Send/Sync impls
     REFERENCE "../dev-rust-code-create/references/unsafe-ffi.md"
   IF reviewed code is async (Tokio, futures, select!, channels)
     REFERENCE "../dev-rust-code-create/references/async.md"
   IF reviewed code uses threads, locks, atomics, or lock-free structures
     REFERENCE "../dev-rust-code-create/references/concurrency.md"
   IF reviewed code does sockets, files, processes, signals, or privileges on Linux
     REFERENCE "../dev-rust-code-create/references/systems.md"
   IF performance is in scope (hot path stated, or perf claims in the PR)
     REFERENCE "../dev-rust-code-create/references/performance.md"
   ```

   Load only the `dev-rust-code-create` references the reviewed code actually touches.

3. **Automated leads** (read-only; run the independent ones together):
   - `scripts/review-scan.sh [-l low] <paths>` — unsafe without SAFETY, unsafe Send/Sync,
     transmute/uninit, static mut, unwrap/panic in non-test code, `len() - 1`, blocking calls
     and std lock guards across `.await` in async fns, SQL via `format!`, TLS verification
     off, `sh -c`, unbounded channels, detached spawns, `#[allow]` without reason. Exit 1 =
     high-severity leads present.
   - `../dev-rust-version-migrate/scripts/scan-legacy.sh -t <edition> <paths>` — edition drift
     and superseded patterns (lazy_static, once_cell, async-trait…).
   - If the user agrees to build (it runs `build.rs` and proc macros): the clippy command in
     `references/lints.md`, and `../dev-rust-code-create/scripts/check.sh -W <project>` for
     fmt/clippy/tests (`-m` adds Miri for unsafe code). Compile errors and failing tests are
     blockers. `cargo audit`/`cargo deny check` if installed.

4. **Manual pass** in checklist order (soundness → panics/errors → ownership/resources →
   concurrency/async → integers → security → API → dependencies → tests → performance →
   style). For each changed function ask: what can make it panic; what happens on every error
   path; what if it's cancelled at each `.await`; what is shared across threads and how it's
   synchronized; who can call this `unsafe` and with what inputs; is it tested.

5. **Report** (most severe first):

   ```
   ## Summary
   <1–3 sentences: overall risk, edition/MSRV assumed, what was run (scans, clippy, tests, Miri)>

   ## Findings
   ### [blocker] <title> — path/file.rs:123
   <failure scenario: input/state → consequence>
   Fix: <concrete change, code snippet if short; note if it needs an MSRV bump>

   ### [major] …

   ## Not checked
   <e.g. did not build (no approval); C side of FFI not reviewed; Miri not run>
   ```

   If nothing significant is found, say so plainly and list what was checked.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/review-scan.sh [-l level] [-T] [-q] [-C] <paths…>` | heuristic risk scan (high/medium/low) with advice per hit; test code exempt from panic/style rules unless `-T` |
| `../dev-rust-version-migrate/scripts/scan-legacy.sh` | edition / superseded-pattern drift scan |
| `../dev-rust-code-create/scripts/check.sh` | fmt + clippy + tests (+ Miri, MSRV) gate |
| `../dev-rust-code-create/scripts/api-find.sh` | verify std/crate API claims and their `since` versions |
| `../dev-rust-code-create/scripts/rust-env.sh` | edition, MSRV, toolchain, installed audit tools |
