# Toolchain and MSRV upgrades

Upgrading rustc almost never breaks compiling code (Rust's stability promise), but it can:
add new warnings (fatal under `-D warnings`), turn future-incompatibility lints into errors,
change inference in rare cases, change lld/linker defaults, and — via the MSRV-aware resolver
— change which dependency versions get selected. Raising `rust-version` is a semver-relevant
decision for published libraries (many treat an MSRV bump as minor, some as major) — ask.

## Pins to update together

| File | Field |
|---|---|
| `Cargo.toml` / `[workspace.package]` | `rust-version = "1.xx"` (MSRV) |
| `rust-toolchain.toml` | `channel = "1.xx.y"` (+ `components`, `targets`) |
| `clippy.toml` | `msrv = "1.xx"` (only if Cargo.toml lacks rust-version) |
| CI (`.github/workflows`, Cloud Build, Jenkins) | toolchain matrix (stable + MSRV job) |
| `mise.toml` / `.tool-versions` / Dockerfile `FROM rust:1.xx` | tool pins |
| `README` | "requires Rust 1.xx" |

Note: a globally exported `RUSTUP_TOOLCHAIN` overrides `rust-toolchain.toml` —
`../dev-rust-code-create/scripts/rust-env.sh` warns about it.

## Procedure

1. Read what changed between the versions:
   `../dev-rust-code-create/scripts/releases.sh -s 'compat|language|cargo' <from>..<to>`.
   "Compatibility Notes" list everything that can break builds.
2. Ask before installing the target toolchain (`rustup toolchain install 1.xx`). Build and
   test with it: `RUSTUP_TOOLCHAIN=1.xx ../dev-rust-code-create/scripts/check.sh -W .`.
3. Fix new warnings/lints (clippy adds lints every release). Don't blanket-`allow`; use
   `#[expect(…, reason)]` when a lint is wrong for a site.
4. Bump `rust-version` only as far as needed; then adopt newer std APIs (table below) where
   they remove dependencies or unsafe code — `scripts/scan-legacy.sh -k superseded -m <new>`
   lists candidates.
5. With resolver 3, re-resolve (`cargo update`) and review `Cargo.lock` changes; verify the
   MSRV build: `cargo msrv verify` (cargo-msrv installed here) or `check.sh -M`.
6. Nightly-only projects: remove `#![feature(x)]` gates that have since stabilized
   (`releases.sh -g '<feature name>'`); the compiler warns `the feature x has been stable since`.

## Finding the right MSRV

- `cargo msrv find` (bisects installed/downloaded toolchains — downloads: ask first).
- Per API: `../dev-rust-code-create/scripts/api-find.sh <name>` shows
  `#[stable(since = "1.xx")]`; `releases.sh -g <name>` shows the release it landed in.
- Dependencies set a floor: `cargo metadata --format-version 1 | jq -r '.packages[] |
  select(.rust_version) | "\(.rust_version) \(.name)"' | sort -V | tail`.

## std replacements by version (drop the dependency or helper once MSRV allows)

| MSRV | Replace | With |
|---|---|---|
| 1.59 | `num_cpus` | `std::thread::available_parallelism` |
| 1.63 | `crossbeam::scope` (for simple cases) | `std::thread::scope` |
| 1.65 | `if let … else { return }` ladders | `let … else` |
| 1.68 | `pin_utils::pin_mut!` | `std::pin::pin!` |
| 1.70 | `atty`, `is-terminal` | `std::io::IsTerminal` |
| 1.70 | `once_cell::sync::OnceCell` | `std::sync::OnceLock` |
| 1.74 | `[lints]` in `.cargo/config` rustflags | `[lints]` in Cargo.toml |
| 1.75 | `async-trait` (static dispatch only) | native `async fn` in traits |
| 1.77 | `memoffset` | `std::mem::offset_of!` |
| 1.77 | `cstr!` macros | `c"…"` literals |
| 1.79 | `static_assertions` | `const { assert!(…) }` |
| 1.80 | `lazy_static`, `once_cell::sync::Lazy` | `std::sync::LazyLock` |
| 1.81 | `#[allow]` | `#[expect(lint, reason = "…")]` |
| 1.82 | `ptr::addr_of!`/`addr_of_mut!` | `&raw const`/`&raw mut` |
| 1.85 | `F: Fn() -> Fut` async callbacks | async closures, `AsyncFn*` |
| 1.87 | `os_pipe` | `std::io::pipe` |
| 1.88 | `#[bench]` | criterion/divan |
| 1.89 | `fs2`/`fs4`/`fd-lock` (basic locking) | `File::lock`/`try_lock`/`lock_shared` |
| 1.95 | `cfg-if` | `cfg_select!` |
| 1.96 | `assert!(matches!(…))`, `assert_matches` crate | `assert_matches!` |

Verify each row with `api-find.sh`/`releases.sh` before relying on it.
