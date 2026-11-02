# Threads, synchronization, atomics, lock-free

`Send`/`Sync` make data races a compile error; deadlocks, livelocks, contention, and wrong
memory orderings are still yours. Measure contention before optimizing it.

## Choosing a model

| Workload | Tool |
|---|---|
| Data-parallel CPU work over collections | `rayon` (`par_iter`, `par_chunks`, `join`) |
| A few long-lived workers | `std::thread::spawn` + channels |
| Workers that borrow from the caller's stack | `std::thread::scope` (no `Arc`/`'static` needed) |
| Many concurrent I/O tasks | async runtime (`async.md`) |
| Pipeline stages | bounded channels between threads (`std::sync::mpsc::sync_channel`, `crossbeam-channel`) |
| Shared read-mostly config | `Arc<T>` immutable; swap whole values with `arc-swap` |

- Size pools with `std::thread::available_parallelism()` (cgroup-aware on Linux), not a constant.
- Name threads (`thread::Builder::new().name(..)`) for debuggers/profilers; join every handle
  and propagate panics (`handle.join()` returns `Err` on panic).

## Locks

- `std::sync::Mutex`/`RwLock` are futex-based and fast; `parking_lot` adds no-poisoning,
  fairness controls, and smaller size. Don't switch without a reason.
- Keep critical sections short; never call unknown code (callbacks, I/O, logging sinks that
  lock) while holding a lock. Clone/compute outside, lock to swap/insert.
- Lock ordering: document a global order when holding more than one lock; or restructure so
  only one is needed. `try_lock` loops are a smell.
- `RwLock` only helps with long read sections and rare writes; under heavy contention a
  `Mutex` or sharding (`[Mutex<T>; N]` indexed by hash, or `dashmap`) is often faster.
  `RwLockWriteGuard::downgrade` *(1.92)*.
- `Condvar` always in a `while !condition` loop (spurious wakeups); prefer channels or
  `Barrier`/`OnceLock`/`std::sync::mpsc` when they fit.
- Poisoning policy: see `errors.md`.

## Atomics and memory ordering

| Ordering | Use |
|---|---|
| `Relaxed` | counters/statistics, IDs — no other memory depends on the value |
| `Release` (store) / `Acquire` (load) | publish data: writes before the Release store are visible after the Acquire load that reads it |
| `AcqRel` | read-modify-write that both consumes and publishes (`fetch_add` on a refcount drop, CAS in lock-free structures) |
| `SeqCst` | needs a single global order across *multiple* atomics (rare; e.g. Dekker-style flags) |

- Default to `Acquire`/`Release` pairs and justify `Relaxed` in a comment. `SeqCst` everywhere
  is not "safer" — it hides that nobody reasoned about the protocol.
- A flag with `Relaxed` that guards non-atomic data is a bug.
- `compare_exchange_weak` in retry loops; `fetch_update`/`update` *(1.95)* for closures.
- `AtomicPtr` + `Box::into_raw` lock-free structures need safe memory reclamation
  (`crossbeam-epoch`, hazard pointers, or `arc-swap`) — freeing on pop is a use-after-free.
- Avoid false sharing on hot per-thread counters: `crossbeam_utils::CachePadded<T>` or
  `#[repr(align(128))]`.
- Prefer existing structures: `crossbeam` (queues `ArrayQueue`/`SegQueue`, channels, epoch),
  `flume`, `dashmap`, `arc-swap`, `thread_local`/`thread_local!` for per-thread state.

## Verifying concurrent code

- `loom` model-checks atomics/locks by exhaustively exploring interleavings: write small
  `loom::model(|| …)` tests behind `#[cfg(loom)]`, run `RUSTFLAGS="--cfg loom" cargo test --release`.
- Miri detects data races and some weak-memory bugs in unsafe/atomic code
  (`cargo +nightly miri test`).
- ThreadSanitizer: `RUSTFLAGS="-Zsanitizer=thread" cargo +nightly test -Zbuild-std --target
  x86_64-unknown-linux-gnu` (needs nightly `rust-src`).
- Stress tests: run the test in a loop with many threads; `--test-threads=1` only to isolate.

## `Send`/`Sync` cheat sheet

- `Rc`, `RefCell` guards, raw pointers: `!Send`. `Cell`/`RefCell`: `Send` but `!Sync`.
- `Arc<T>` is `Send + Sync` only if `T: Send + Sync`. `Mutex<T>` is `Sync` if `T: Send`.
- `unsafe impl Send/Sync for X {}` needs a `// SAFETY:` argument covering every field and
  every method that touches shared state; it is the most common source of unsound crates.
