# Testing, fuzzing, and debugging

## Test layout

- Unit tests next to the code: `#[cfg(test)] mod tests { use super::*; … }` at the end of the
  file — they can test private items.
- Integration tests in `tests/*.rs` use only the public API (one crate per file; shared
  helpers in `tests/common/mod.rs`).
- Doc tests in `///` examples are compiled and run; they are the best API usage tests. Use
  `?` in doctests with a hidden `# Ok::<(), Box<dyn std::error::Error>>(())` line.
- Name tests by behavior: `rejects_port_zero`, not `test1`. One logical assertion per test;
  `assert_eq!(got, want, "context")`.
- Tests return `Result<(), E>` to use `?` instead of `unwrap()` chains.
- `#[should_panic(expected = "…")]` only for documented panics; prefer testing `Err` variants
  with `assert!(matches!(r, Err(E::Invalid(_))))` or `assert_matches!` *(1.96)*.
- Filesystem tests: `tempfile::tempdir()`; never write into the repo or `$HOME`.
- Snapshot tests for large outputs: `insta` (`cargo insta review` if installed).

## Running

```bash
cargo test                          # all unit + integration + doc tests
cargo test -p crate parse_          # filter by name substring
cargo test -- --nocapture           # show println!/dbg! output
cargo test -- --test-threads=1      # serialize (tests sharing global state — fix that instead)
cargo nextest run                   # faster, per-test processes, retries; no doctests (run cargo test --doc)
cargo test --doc
```

`scripts/check.sh` runs fmt → clippy → nextest/test (+ doctests) with timeouts.

## Property-based testing

`proptest` (or `quickcheck`) for parsers, encoders, data structures, and math:

```rust
proptest! {
    #[test]
    fn roundtrip(msg in any::<Message>()) {           // derive Arbitrary or write a strategy
        let bytes = encode(&msg);
        prop_assert_eq!(decode(&bytes)?, msg);
    }
}
```

Good properties: round-trips, invariants preserved (sorted, len), equivalence with a
simple reference implementation, idempotence, no panic on arbitrary input. Commit
`proptest-regressions/` files.

## Fuzzing

- `cargo fuzz` (libFuzzer, nightly; cargo-fuzz not installed here — ask before installing):
  `cargo fuzz init`, targets in `fuzz/fuzz_targets/*.rs`, `cargo +nightly fuzz run target -- -max_total_time=60`.
- Use `arbitrary::Arbitrary` to fuzz structured input; seed the corpus with real samples.
- Every parser of untrusted input (network, files, CLI) should have a fuzz target; a found
  crash becomes a regular unit test.
- Alternatives: `afl.rs`, `bolero` (unifies proptest/libFuzzer/AFL/Kani).

## Undefined-behavior and concurrency checking

- **Miri** (`cargo +nightly miri test`, installed here): interprets tests and detects UB —
  out-of-bounds, use-after-free, invalid values, aliasing violations (Stacked/Tree Borrows),
  data races, leaks. Run on every crate with `unsafe`. Miri can't call most FFI; gate those
  tests with `#[cfg_attr(miri, ignore)]`. Slow: filter tests.
- **Sanitizers** (nightly): `RUSTFLAGS=-Zsanitizer=address|thread|memory|leak`, with
  `--target x86_64-unknown-linux-gnu` (and `-Zbuild-std` for thread/memory).
- **loom** for lock-free/atomic protocols (`concurrency.md`).
- **Kani** model checker for proving small unsafe functions (if installed).

## Coverage

`cargo llvm-cov` (if installed; `--html`, `--lcov` for CI) or `RUSTFLAGS="-C
instrument-coverage"` + `grcov`. Use coverage to find untested error paths, not as a target.

## Async tests

`#[tokio::test]`; `#[tokio::test(start_paused = true)]` or `tokio::time::pause()` for
deterministic timers (`test-util` feature). Bound every await in tests with
`tokio::time::timeout` so a hang fails instead of stalling CI.

## Debugging

- Read the *first* compiler error; `rustc --explain E0xxx`. For trait-bound errors, read the
  "required by" chain bottom-up. `cargo check --message-format=short` for a quick list.
- Macro errors: `cargo expand path::to::item`.
- Backtraces: `RUST_BACKTRACE=1` (or `full`); `RUST_LIB_BACKTRACE=1` for anyhow/eyre errors.
- Debuggers: `rust-gdb`/`rust-lldb` (pretty-printers for std types) on a debug build;
  `CLion`/`RustRover` or VS Code + CodeLLDB. `dbg!(expr)` for quick prints (remove before done).
- Logging in tests: `tracing-subscriber` with `with_test_writer()`, or `test-log`.
- Flaky tests: run under `cargo nextest run --retries 0 --no-fail-fast` in a loop; look for
  shared global state, ports, time, or ordering of `HashMap` iteration.
