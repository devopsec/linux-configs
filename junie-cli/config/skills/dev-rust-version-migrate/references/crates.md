# Upgrading dependencies across major versions

`cargo update` stays within semver-compatible ranges (`1.2` → `1.9`, `0.12.1` → `0.12.9`);
crossing a major (`0.12` → `0.13`, `1` → `2`) requires editing `Cargo.toml` and porting code.
Upgrade one crate (or one tightly coupled family: `hyper`+`http`+`http-body`,
`axum`+`tower-http`, `tonic`+`prost`) at a time, and compile between steps.

## Procedure

1. Inventory: `cargo tree -d` (duplicate majors), `cargo outdated`/`cargo upgrade --dry-run`
   (cargo-edit) if installed, or `cargo info <crate>` (network) for the latest version.
2. Read the crate's `CHANGELOG.md`/release notes for every major between the versions. After
   `cargo fetch`, the new version's source and changelog are local:
   `../dev-rust-code-create/scripts/api-find.sh -c <crate> <item>`.
3. Edit the version (`cargo add crate@X` keeps features) and its family; `cargo check
   --all-targets --all-features`; fix errors file by file, reading the *first* error.
4. Search for deprecated-but-compiling APIs (`cargo clippy` shows `deprecated` warnings) and
   behavior changes the changelog lists (defaults, feature names, error types, MSRV).
5. Run tests; for public libraries, if your public API exposes the dependency's types, the
   upgrade is a breaking change for *your* users too.
6. Check the new version's `rust-version` against yours (`cargo metadata` or its Cargo.toml).

`scripts/scan-legacy.sh -k crate` flags common rename patterns below; it can't know which
version you're on — only act on hits for crates you are upgrading.

## Known major-version changes (verify in the changelog at the target version)

| Crate | From → to | What changes |
|---|---|---|
| `rand` | 0.8 → 0.9 | `thread_rng()` → `rand::rng()`; `gen()` → `random()`, `gen_range` → `random_range`, `gen_bool` → `random_bool`; `distributions` → `distr`; `rand::random::<T>()` stays |
| `axum` | 0.7 → 0.8 | path syntax `/:id` → `/{id}`, `/*rest` → `/{*rest}`; `#[async_trait]` removed from `FromRequest(Parts)` impls; `Option<T>` extractor requires `OptionalFromRequestParts` |
| `hyper` | 0.14 → 1.x | `Body` → `hyper::body::Incoming` + `http_body_util::{Full, Empty, BodyExt}`; server/client high-level APIs moved to `hyper-util` (`server::conn::auto`, `client::legacy`); `to_bytes` → `body.collect().await?.to_bytes()` |
| `http` | 0.2 → 1.x | moves with hyper 1 / axum 0.7+; types not interchangeable across majors |
| `base64` | < 0.21 → 0.21+ | free fns `encode`/`decode` → `Engine` trait: `general_purpose::STANDARD.encode(x)` |
| `clap` | 2/3 / structopt → 4 | derive: `#[derive(Parser)]`, `#[command(...)]` on structs, `#[arg(...)]` on fields, `ArgAction` for flags/counts |
| `tokio` | 0.2/0.3 → 1 | `delay_for` → `sleep`, runtime builder methods, `io::split` vs `into_split`; 1.x is stable — stay on 1 |
| `thiserror` | 1 → 2 | mostly compatible; `no_std` support; check `#[error]` format-string edge cases with raw identifiers |
| `nix` | ≤0.26 → 0.27+ | `RawFd` → `OwnedFd`/`BorrowedFd`/`AsFd` in many APIs; modules behind cargo features |
| `chrono` | 0.4.x (deprecations from 0.4.35) | `Utc::today()` → `Utc::now().date_naive()`; `NaiveDateTime::from_timestamp` → `DateTime::from_timestamp`; `*_opt` constructors |
| `reqwest` | 0.11 → 0.12 | built on hyper 1 / http 1; check TLS feature names (`rustls-tls` variants) |
| `tonic`/`prost` | each minor (0.x) | lockstep versions with `tonic-build`/`prost-build`; regenerate code |
| `bitflags` | 1 → 2 | flags are a generated struct type; `bits()` etc. changed; derive traits explicitly |
| `syn` | 1 → 2 | proc-macro authors: `Attribute::parse_args`, `Meta` API reshaped |
| `serde_yaml` | — | unmaintained: evaluate `serde_yml`/`serde_norway` or another format |

Treat the table as orientation from mid-2025 knowledge; the changelog at the locked target
version wins.
