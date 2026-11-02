# Rust review checklist

Ordered by severity. Each item: what to look for → why it matters → the fix to suggest.
API names and `(1.xx)` markers assume a recent stable; check the project's MSRV before
suggesting a newer API (`../dev-rust-code-create/scripts/api-find.sh` shows `since`).

## Contents
1. Soundness and unsafe
2. Panics and error handling
3. Ownership, resources, and lifetimes
4. Concurrency and async
5. Integer, casting, and indexing
6. Security and untrusted input
7. API design
8. Dependencies, features, and Cargo hygiene
9. Tests
10. Performance
11. Style, docs, and idioms

## 1. Soundness and unsafe (blocker)

- [ ] Every `unsafe` block has a `// SAFETY:` comment naming the preconditions and why they
      hold *here*; the argument is actually correct (check aliasing, alignment, lifetime,
      initialization, bounds).
- [ ] Safe public functions cannot cause UB for any input — otherwise they must be `unsafe fn`
      with a `# Safety` doc section. A private invariant that safe code in the same module can
      break (e.g. a `pub` field that unsafe code trusts) is unsound.
- [ ] `unsafe impl Send/Sync` is justified for every field and every `&self` method.
- [ ] No `transmute` between types without guaranteed layout; no `mem::zeroed`/`uninitialized`
      for types with invalid zero values; `MaybeUninit` read only after full initialization.
- [ ] `from_raw_parts`/`set_len`/`Box::from_raw`/`CString::from_raw` receive exactly what
      the matching `into_raw`/allocation produced (same allocator, length, capacity, layout).
- [ ] References created from raw pointers have bounded lifetimes (tied to `&self`), and no
      `&mut` aliases another live reference.
- [ ] FFI: `#[repr(C)]` on shared types, no Rust enums receiving arbitrary C integers, no
      panics unwinding through `extern "C"`, `CString` kept alive while C uses the pointer,
      ownership/free functions matched.
- [ ] Panic safety in unsafe code: a panic midway (user callback, `clone`, allocation) cannot
      leave memory double-freed or uninitialized-but-reachable (guards restore invariants).
- [ ] `static mut`, `env::set_var` in multi-threaded code, `#[no_mangle]` symbol clashes.
- [ ] Miri ran on tests that exercise the unsafe code (or a reason why it can't).

## 2. Panics and error handling (blocker → major)

- [ ] No `unwrap()`/`expect()`/`panic!`/`todo!`/`unimplemented!` reachable from input, I/O,
      network, env, config, or parsing in non-test code. `expect` messages state the invariant.
- [ ] No indexing (`v[i]`, `&s[a..b]`), `len() - 1`, division, or `as`-narrowing that panics
      or wraps on attacker/user-controlled values; string slicing on char boundaries.
- [ ] Errors are not swallowed: no `let _ = fallible();`, `.ok();`, `unwrap_or_default()` on
      operations whose failure matters, `if let Ok(..)` without an else that reports.
- [ ] Error types: libraries expose typed errors (enum, `#[non_exhaustive]`), applications
      add context (`with_context`); source chains preserved (`#[source]`), not stringified.
- [ ] Lock poisoning handled deliberately (documented `expect` or `into_inner`).
- [ ] `main` returns `Result`/`ExitCode` rather than `process::exit` with pending destructors.
- [ ] Public functions document `# Errors` and `# Panics` (libraries).

## 3. Ownership, resources, and lifetimes (major)

- [ ] `clone()`, `to_owned()`, `Rc<RefCell<_>>`, `Arc<Mutex<_>>`, or `'static` added only to
      satisfy the borrow checker → suggest the borrow-shortening or restructuring instead.
- [ ] Parameters borrow (`&str`, `&[T]`, `&Path`, `impl AsRef`) unless ownership is needed.
- [ ] Resources released on every path: files/sockets via RAII; `BufWriter` flushed and the
      flush error checked; temp files cleaned; child processes waited.
- [ ] Unbounded growth: caches without eviction, `Vec`s that only grow, `Box::leak`/`mem::forget`
      per request, `HashMap` keyed by attacker input without limits.
- [ ] Edition 2024 drop-order changes (tail-expression and `if let` temporaries) don't
      release a guard earlier/later than the logic assumes.

## 4. Concurrency and async (blocker → major)

- [ ] No blocking calls in `async fn` (std::fs, std::thread::sleep, blocking HTTP, heavy CPU,
      `std::sync::mpsc::recv`) → async equivalent or `spawn_blocking`.
- [ ] No `std::sync::Mutex` guard held across `.await`; `tokio::sync::Mutex` only when the
      lock must span an await.
- [ ] Cancellation safety: futures in `select!` loops are cancel-safe; state stays consistent
      if any `.await` is the last one to run (timeouts, client disconnects).
- [ ] Backpressure and limits: bounded channels, semaphores, `buffer_unordered(n)`, connection
      limits, timeouts on every network call.
- [ ] Spawned tasks/threads are joined or owned (`JoinSet`), their errors/panics observed,
      and shut down on exit (cancellation token / channel close).
- [ ] Lock ordering consistent; no callbacks/I/O under a lock; no `RwLock` writer starvation
      in hot paths.
- [ ] Atomics: orderings justified (`Relaxed` only when nothing else depends on the value;
      Release/Acquire pairs for publication); lock-free code has memory reclamation and loom
      or Miri tests.
- [ ] Data shared across threads is `Send + Sync` for the right reason, not via `unsafe impl`.

## 5. Integer, casting, and indexing (major)

- [ ] `as` casts between integer widths/signs or float→int on untrusted values → `try_from`.
- [ ] Arithmetic on sizes/offsets/lengths from input uses `checked_*` (release builds wrap
      silently unless `overflow-checks = true`).
- [ ] Peer-supplied lengths are bounded before `Vec::with_capacity`/allocation.

## 6. Security and untrusted input (blocker → major)

- [ ] SQL via bind parameters, never `format!`. Shell commands via `Command::new(prog).args()`,
      never `sh -c` with interpolated input; program paths not user-controlled.
- [ ] Path traversal: user paths joined onto a base are canonicalized and prefix-checked (or
      opened with `openat2`/`RESOLVE_BENEATH`); `Path::join` with an absolute path replaces the base.
- [ ] TLS verification on (`danger_accept_invalid_certs(false)`); rustls/native-tls config sane.
- [ ] Secrets not logged (`Debug` derives on config structs), not hardcoded, zeroized when
      practical; constant-time comparison (`subtle`) for MACs/tokens.
- [ ] Deserialization of untrusted data bounds sizes/depth (`serde_json` recursion limit is on
      by default; custom formats need limits); `#[serde(deny_unknown_fields)]` where strictness
      matters.
- [ ] File permissions for sensitive files set at creation (`mode(0o600)`).
- [ ] Regexes from user input use `regex` (linear time), not backtracking engines.
- [ ] `cargo audit`/`cargo deny check` clean (if installed) — known-vulnerable or yanked crates.

## 7. API design (major → minor)

- [ ] Invalid states unrepresentable (enums, newtypes, constructors that validate).
- [ ] Public types derive/implement `Debug` and the common traits that make sense; public
      enums/structs that may grow are `#[non_exhaustive]`; `#[must_use]` on builders/results.
- [ ] Conversions via `From`/`TryFrom`/`FromStr`/`AsRef`, not ad-hoc `to_x()` methods; no
      `Into` impls; no bool parameters where an enum reads better.
- [ ] Public API doesn't leak dependency types unintentionally (semver coupling); `pub` is as
      narrow as possible (`pub(crate)`).
- [ ] Async traits: `Send` bounds where callers spawn; dyn-compatibility where needed.
- [ ] Semver: for published crates, breaking changes are intended (`cargo semver-checks` if
      installed).

## 8. Dependencies, features, and Cargo hygiene (minor → major)

- [ ] New dependencies are justified, maintained, license-compatible, and minimal in default
      features; no duplicate major versions added without reason (`cargo tree -d`).
- [ ] Features are additive; `dep:` syntax for optional deps; code compiles with
      `--no-default-features` and `--all-features`.
- [ ] Code uses no std API newer than `rust-version` and no edition-2024 syntax in a 2021
      crate (`scripts/scan-legacy.sh` in dev-rust-version-migrate covers the reverse).
- [ ] `Cargo.lock` committed for binaries; `build.rs` declares `rerun-if-changed`, doesn't
      download or write outside `OUT_DIR`.
- [ ] Lint configuration (`[lints]`) not weakened; new `#[allow]` have reasons → prefer
      `#[expect(..., reason = "...")]` (1.81+).

## 9. Tests (major)

- [ ] New logic and every fixed bug have tests; error paths and edge cases (empty, max,
      unicode, malformed) are covered.
- [ ] Parsers/decoders of untrusted input have property tests or fuzz targets.
- [ ] Tests are deterministic (no real network/time/global state; `tempfile` for FS;
      paused Tokio time) and bounded by timeouts in async code.
- [ ] Unsafe code covered by tests that run under Miri.

## 10. Performance (minor unless on a stated hot path)

- [ ] Allocations/clones/`format!` inside hot loops; `collect()` then iterate; `Vec<Box<T>>`
      / linked structures where a flat `Vec` works.
- [ ] Missing `with_capacity` for known sizes; `String` building with `+`.
- [ ] Locks or atomics contended on every request; `Arc` clones per item in tight loops.
- [ ] Claims of speedups come with benchmark numbers; `unsafe` for speed has a measured win.

## 11. Style, docs, and idioms (nit unless it hurts readability)

- [ ] `cargo fmt` clean; clippy clean at the project's lint level.
- [ ] Idioms: `?` over `match` on errors, iterator adaptors over index loops when clearer,
      `if let`/`let else`, `matches!`, `Option` combinators without obscuring logic.
- [ ] Naming per API guidelines (`as_`/`to_`/`into_` conventions, `snake_case`, no `get_`
      prefix for plain getters).
- [ ] Public items documented with examples (doctests); module docs explain invariants.
- [ ] No leftover `dbg!`, `println!` in libraries, commented-out code, or stale TODOs.
