---
name: dev-rust-version-migrate
description: "Port Rust crates and workspaces to a newer edition (2015 → 2018 → 2021 → 2024), raise the toolchain/MSRV (rust-version, rust-toolchain.toml, CI pins) and adopt std replacements (LazyLock, OnceLock, IsTerminal, offset_of!, cfg_select!, native async-fn-in-trait), or upgrade dependencies across major versions (rand 0.9, axum 0.8, hyper 1, base64 Engine, clap 4, nix OwnedFd, chrono deprecations). Use when asked to upgrade/migrate/port a Rust project to edition 2024 or a newer Rust, run cargo fix --edition, fix errors after a toolchain or dependency bump, find or raise the MSRV, drop lazy_static/once_cell/async-trait/cfg-if, or explain what changed between Rust versions or editions. For writing new code use dev-rust-code-create; for reviews use dev-rust-code-review."
---

# Rust edition, toolchain, and dependency migration

Three different upgrades, each done separately and verified before the next:
1. **Edition** (per crate; `cargo fix --edition` does most of it),
2. **Toolchain/MSRV** (rarely breaks code; changes lints, resolver choices, available APIs),
3. **Dependency majors** (the real porting work; one crate family at a time).

Never mix them in one step, and never refactor beyond what the port needs.

## Ground rules

- Confirm source and target first: current edition, `rust-version`, toolchain pin, and the
  target the user wants. Default edition target = 2024 (needs rustc ≥ 1.85); don't raise
  MSRV beyond what's needed, and ask before raising it for a published library.
- Establish context with `../dev-rust-code-create/scripts/rust-env.sh <project>` (exit 3 =
  toolchain mismatch / env override / MSRV above installed rustc → resolve with the user first).
- The compiler is the final judge: `scripts/scan-legacy.sh` plans, `cargo fix` applies the
  mechanical part, the build/tests find the rest.
- Start from a clean tree with passing tests on the old setup, so every new failure is
  attributable to the migration.
- Ask before installing toolchains/targets/cargo subcommands, and before `cargo update`
  that changes many lockfile entries in an application with pinned deployments.
- Call out behavior changes that compile silently (drop-order changes in 2024, closure
  capture changes in 2021, feature resolver changes, never-type fallback) in the report.

## Workflow

1. **Establish versions**: edition(s) per crate (`rust-env.sh -f edition`), `rust-version`,
   toolchain pins, CI matrix. Scan for the full picture:
   `scripts/scan-legacy.sh -f <from-edition> -t <to-edition> -m <target-msrv> <project>`.

2. **Load the notes for the requested upgrade(s)**:

   ```sadkitti
   IF moving to a newer edition
     REFERENCE "references/editions.md"
   IF raising MSRV / rust-version / toolchain pin, or adopting newer std APIs, or removing nightly feature gates
     REFERENCE "references/toolchain.md"
   IF upgrading a dependency across a major version (or fixing errors after one)
     REFERENCE "references/crates.md"
   IF writing new code during the port
     REFERENCE "../dev-rust-code-create/SKILL.md"
   ```

3. **Edition step** (repeat per edition and per crate, leaf crates first):
   1. `cargo fix --edition --all-features --all-targets -p <crate>` (on the old edition).
   2. Set `edition` (and for 2024: `rust-version >= 1.85`, `resolver = "3"` in virtual
      workspaces).
   3. Work the `manual` hits of `scan-legacy.sh` and remaining compiler errors.
   4. `cargo fmt` (2024 style edition; separate commit-sized change) and `cargo clippy`.
   5. Tests pass before the next crate/edition.

4. **Toolchain/MSRV step**: read `releases.sh -s 'compat|language|cargo' <from>..<to>`;
   build/test on the new toolchain; fix new lints; bump pins together (Cargo.toml,
   rust-toolchain.toml, CI, mise/Docker); then optionally replace `superseded` hits
   (`scan-legacy.sh -k superseded -m <new msrv>`), one replacement kind at a time.

5. **Dependency step**: per crate family — read its changelog, bump, `cargo check`, fix,
   test; use `scan-legacy.sh -k crate` hits only for the crate being upgraded.

6. **Verify** with the final setup: `../dev-rust-code-create/scripts/check.sh -W -M <project>`
   (fmt, clippy, tests, MSRV build if that toolchain is installed); re-run
   `scan-legacy.sh -k edition,manual -f <old> -t <new>` → expect zero (explain any
   remaining false positives).

7. **Report**: what moved (edition/MSRV/deps, old → new per crate), files changed, scan
   summary before/after, behavior changes that compile silently, lints newly allowed (with
   reasons), deprecated APIs intentionally left, and tests/builds run (or why not).

## Scripts

| Script | Purpose |
|---|---|
| `scripts/scan-legacy.sh [-f ed] [-t ed] [-m msrv] [-k kinds] [-q] [-C] <paths…>` | inventory of edition breaks (2018/2021/2024, `.rs` and `Cargo.toml`), std-superseded crates/patterns gated by MSRV, deprecated std APIs, and common crate major-version renames, with the fix per hit |
| `../dev-rust-code-create/scripts/releases.sh` | release notes by version range / grep (compatibility notes) |
| `../dev-rust-code-create/scripts/api-find.sh` | confirm replacements and their `since` in std or the upgraded crate |
| `../dev-rust-code-create/scripts/check.sh` | fmt + clippy + tests (+ MSRV build) |

Coverage gaps the scanner cannot see: disjoint closure capture and drop-order changes,
never-type fallback, RPIT lifetime capture, match-ergonomics reservations, method-resolution
changes from prelude additions, and APIs reached through re-exports or aliases. The compiler
(after `cargo fix --edition`) and the tests catch these.
