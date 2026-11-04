# Cargo projects, workspaces, features, profiles

Check `cargo <cmd> --help` and the local Cargo book (`<docs>/cargo/`) for the installed version.

## New projects

```bash
cargo new --bin app            # or --lib; creates .gitignore (target/) and git repo unless --vcs none
cargo new --lib crates/core    # inside a workspace: also adds it to [workspace] members
```

Minimal modern manifest:

```toml
[package]
name = "app"
version = "0.1.0"
edition = "2024"
rust-version = "1.85"          # MSRV: lowest rustc you test; 2024 edition needs >= 1.85
license = "MIT OR Apache-2.0"
description = "…"              # required to publish
publish = false                # for internal crates

[dependencies]
anyhow = "1"                   # caret: "1" = >=1.0.0,<2; "0.12" = >=0.12,<0.13
serde = { version = "1", features = ["derive"] }

[dev-dependencies]
proptest = "1"

[lints]
workspace = true               # or a [lints.rust]/[lints.clippy] table here
```

- Add deps with `cargo add <crate>[@ver] [-F feat]` (edits Cargo.toml, respects MSRV with the
  v3 resolver); remove with `cargo remove`. Ask before adding dependencies.
- `Cargo.lock`: commit it for binaries and workspaces with binaries; for libraries committing
  is also the current recommendation (CI reproducibility).
- `cargo update -p <crate>` for one crate; `--precise <ver>` to pin. `cargo tree -i <crate>`
  shows who pulls it in; `cargo tree -d` shows duplicate versions.

## Workspaces

```toml
# root Cargo.toml (virtual manifest)
[workspace]
resolver = "3"                 # default for edition 2024 packages; set explicitly in virtual manifests
members = ["crates/*"]

[workspace.package]
edition = "2024"
rust-version = "1.85"
license = "MIT OR Apache-2.0"

[workspace.dependencies]
tokio = { version = "1", default-features = false }
thiserror = "2"

[workspace.lints.rust]
unsafe_code = "forbid"
[workspace.lints.clippy]
all = { level = "warn", priority = -1 }
```

Members: `edition.workspace = true`, `tokio = { workspace = true, features = ["rt"] }`.
In edition 2024, `default-features = false` on an inherited dependency is an error unless the
workspace entry also sets it (1.99 allows edition-2024 members to override it). Features are
unified across everything built together — `cargo build -p a` and a full-workspace build can
compile a dependency with different features.

## Features

- Additive only: enabling a feature must never remove API or change behavior incompatibly.
- Optional deps: `foo = { version = "1", optional = true }` + `[features] foo = ["dep:foo"]`
  (the `dep:` prefix avoids an implicit feature named after the crate).
- Enable a dependency's feature only when that dependency is enabled: `"serde?/derive"`.
- Keep `default` small for libraries; document features in the crate docs.
- CI: `cargo hack check --feature-powerset` (if installed) or at least `--no-default-features`
  and `--all-features`.
- `#[cfg(feature = "x")]` names are checked against the manifest (`unexpected_cfgs`); declare
  custom cfgs via `[lints.rust] unexpected_cfgs = { level = "warn", check-cfg = ['cfg(tokio_unstable)'] }`.

## Profiles

```toml
[profile.release]
lto = "thin"            # "fat" for max perf, slower builds
codegen-units = 1       # better optimization, slower build
panic = "abort"         # smaller/faster, no unwinding (breaks catch_unwind)
debug = "line-tables-only"   # usable backtraces/profiles at little cost
strip = "symbols"       # smaller binaries (drop when profiling)

[profile.dev.package."*"]
opt-level = 2           # optimize deps in dev builds (fast tests for heavy deps)

[profile.profiling]
inherits = "release"
debug = true
strip = "none"
```

- `overflow-checks = true` in release for code where wrapping would be a security bug.
- 1.99 adds a built-in `debug` profile in preparation for a faster default `dev` profile; check
  the Cargo book of the installed version before relying on `dev` debug-info defaults.
- Build-time: the Cargo book's "Optimizing Build Performance" chapter (1.92+); `cargo build
  --timings`; `lld` is the default linker on x86_64-linux since 1.90; `mold` via
  `-C link-arg=-fuse-ld=mold` if installed.

## Build scripts and targets

- `build.rs` only for codegen, native library discovery (`pkg-config` crate), or `cc`
  compilation. Emit `cargo::rerun-if-changed=…` (double colon syntax, 1.77+) or it reruns on
  every change. Never download in build scripts.
- Cross-compiling: `rustup target add <triple>` (ask first) + `cargo build --target <triple>`;
  for C deps use `cargo zigbuild` or `cross` if the user has them. Static Linux binaries:
  `x86_64-unknown-linux-musl`.
- Binaries: `src/main.rs` or `src/bin/*.rs`; examples in `examples/` (`cargo run --example x`);
  integration tests in `tests/`; benches in `benches/` with `harness = false` for criterion/divan.
- `.cargo/config.toml` for per-project settings (`[build] rustflags`, `[target.x] linker`,
  `[alias]`). Prefer `[lints]` and profiles in Cargo.toml over `RUSTFLAGS` (flags change
  invalidate the whole cache).
- `-C target-cpu=native` only for binaries that run on the build host; never for distributed
  artifacts or libraries.

## Useful commands

| Command | Use |
|---|---|
| `cargo check` | fastest type-check; use while iterating |
| `cargo clippy --all-targets --all-features` | lints incl. tests/benches/examples |
| `cargo fmt --all` / `-- --check` | format / verify |
| `cargo test -p crate name_filter -- --nocapture` | one test with output |
| `cargo doc --no-deps --open` | API docs |
| `cargo tree -e features -i <crate>` | why a feature is on |
| `cargo metadata --format-version 1` | machine-readable graph (jq) |
| `cargo expand path::to::mod` | macro expansion (cargo-expand installed here) |
| `cargo msrv verify` / `find` | MSRV check (cargo-msrv installed here) |
| `cargo +nightly udeps` / `cargo machete` | unused deps (if installed) |
