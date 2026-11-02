# Errors and panics

## Policy

- **Recoverable failure → `Result`.** Input, I/O, network, parsing, configuration, resource
  limits. Propagate with `?`.
- **Bug / broken invariant → panic.** Indexing past a length you checked, impossible enum
  states. Prefer `expect("why this cannot fail")` over `unwrap()` so the message explains the
  invariant. Libraries document reachable panics under `# Panics`.
- Never `unwrap()`/`expect()` on: user/network/file input, env vars, lock poisoning in
  library code you don't control, `parse()` of external data, `try_into()` of untrusted sizes.
  OK in tests, examples, build scripts, and on values proven by construction (literal regex).
- No panics across FFI boundaries (UB with `extern "C"`); see `unsafe-ffi.md`.

## Libraries: typed errors (`thiserror`)

```rust
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ConfigError {
    #[error("reading config {path}")]
    Read { path: PathBuf, #[source] source: std::io::Error },
    #[error("invalid port {0}: must be 1-65535")]
    InvalidPort(u32),
    #[error(transparent)]
    Parse(#[from] toml::de::Error),
}
```

- One error enum per module/API boundary, variants callers can act on. Include context
  (path, key, id) in the variant; don't stringify the source into the message — chain it via
  `#[source]`/`#[from]` so reporters print the cause chain.
- Display messages: lowercase, no trailing period, don't repeat the source's message.
- `#[from]` only when the conversion is unambiguous; otherwise `map_err` with context.
- Hand-written `impl std::error::Error` is fine (no dependency): implement `Display` and
  `source()`.
- Don't expose dependency error types in a stable public API unless you re-export them;
  wrap them (`#[error(transparent)] Io(#[from] io::Error)` is fine for std types).
- Check which thiserror major the lockfile has (`scripts/api-find.sh -c thiserror Error`):
  2.x supports `no_std`, raw identifiers in format strings; 1.x is still common.

## Applications: `anyhow` (or `eyre`/`color-eyre`)

```rust
use anyhow::{Context, Result, bail, ensure};

fn load(path: &Path) -> Result<Config> {
    let text = fs::read_to_string(path)
        .with_context(|| format!("reading {}", path.display()))?;
    let cfg: Config = toml::from_str(&text).context("parsing config")?;
    ensure!(cfg.workers > 0, "workers must be > 0");
    Ok(cfg)
}

fn main() -> anyhow::Result<()> { … }   // prints the cause chain on error, exit code 1
```

- Add context at each layer that knows something new (which file, which request).
- `{:#}` prints the chain on one line; `{:?}` prints the chain + backtrace (with
  `RUST_BACKTRACE=1`).
- Downcast (`err.downcast_ref::<io::Error>()`) only at the top for exit codes/retries.
- Don't use `anyhow` in library public APIs — callers can't match on it.

## `?` mechanics

- `?` calls `From::from` on the error: implement `From<SubError> for MyError` (or `#[from]`).
- `?` on `Option` in a function returning `Option`; convert with `ok_or(…)`/`ok_or_else` /
  `bool::then_some`, `bool::ok_or` *(1.98)*.
- `main` and tests may return `Result<(), E: Debug>`; `#[test] fn t() -> Result<(), Box<dyn Error>>`.
- `Result::flatten` *(1.89)* for `Result<Result<T, E>, E>`; `Option::flatten`/`transpose`.

## Lock poisoning

`Mutex::lock()` returns `Err` if a thread panicked while holding it. Common choices:
`.lock().expect("mutex poisoned")` in apps where a panic already means failure;
`.lock().unwrap_or_else(PoisonError::into_inner)` when the data stays valid. `parking_lot`
locks don't poison. Document the choice.

## Exit codes and reporting (binaries)

- `std::process::ExitCode` from `main` for custom codes; avoid `process::exit` in code paths
  that hold buffered writers or need destructors.
- Log the full error chain once, at the top. Don't log-and-return the same error at every layer.
- Set `panic = "abort"` only if you never need `catch_unwind` (e.g. thread pools recovering).
