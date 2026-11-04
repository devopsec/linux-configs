# Async Rust (Tokio)

Tokio 1.x is the default runtime for networked services. Verify every Tokio/ecosystem API at
the locked version: `scripts/api-find.sh -c tokio <name>` (feature-gated items need the right
`features = [...]`). Use async for many concurrent I/O-bound tasks; for CPU-bound parallelism
use threads/rayon (`concurrency.md`). Don't make a small CLI async just to call one HTTP API
if a blocking client fits.

## Runtime setup

```rust
#[tokio::main]                                   // multi-thread runtime, worker per core
async fn main() -> anyhow::Result<()> { … }

#[tokio::main(flavor = "current_thread")]        // single thread: CLIs, tests, !Send futures
```

Explicit builder when you need sizing or several runtimes:
`tokio::runtime::Builder::new_multi_thread().worker_threads(n).enable_all().build()?`.
Libraries never create runtimes; they expose `async fn` and let the binary choose.
Features: start with `["macros", "rt-multi-thread", "net", "io-util", "time", "sync", "signal"]`
as needed — not `"full"` in libraries.

## Rules that prevent the classic bugs

1. **Never block the executor.** No `std::thread::sleep`, blocking `std::fs`/`std::net`,
   CPU loops > ~100µs, or blocking locks held long inside `async fn`. Use `tokio::time::sleep`,
   `tokio::fs` (thread-pool backed), `spawn_blocking` for blocking/CPU work, or rayon +
   `oneshot` for heavy compute.
2. **Don't hold a `std::sync::Mutex` guard across `.await`** (the future becomes `!Send` and
   can deadlock). Lock, copy/modify, drop, then await. Use `tokio::sync::Mutex` only when the
   lock must be held across an await (e.g. serializing access to an I/O handle).
3. **Cancellation is drop.** Any `.await` may be the last thing that runs (timeouts,
   `select!`, task abort, client disconnect). Keep invariants valid at every await point; use
   RAII guards for cleanup; don't leave half-written state.
4. **`select!` branches must be cancel-safe** when used in a loop: `recv()` on mpsc, `accept()`,
   `sleep` are; `read_exact`, `read_to_end`, `write_all`, and most "do X fully" helpers are
   not (partial progress is lost). Pin long-lived futures outside the loop
   (`let fut = pin!(op()); loop { select! { r = &mut fut => …, … } }`) instead of recreating them.
5. **Bound everything.** `mpsc::channel(n)` (backpressure) over `unbounded_channel`; limit
   concurrency with `Semaphore` or `buffer_unordered(n)`; time out every network operation
   (`tokio::time::timeout`).
6. **Spawned tasks need an owner.** Keep `JoinHandle`s or use `JoinSet`, propagate their errors
   and panics (`JoinError::is_panic`), and shut them down on exit. A dropped `JoinHandle`
   detaches the task, it does not cancel it.
7. `tokio::spawn` requires `Send + 'static`: move owned data (`Arc`, clones) into the task.
   `!Send` values (`Rc`, `RefCell` guards) must not live across an await in a spawned task;
   use `LocalSet`/`spawn_local` or a current-thread runtime if unavoidable.

## Patterns

```rust
// Structured fan-out with error propagation
let mut set = tokio::task::JoinSet::new();
for url in urls { let c = client.clone(); set.spawn(async move { fetch(&c, url).await }); }
while let Some(res) = set.join_next().await { res??; }        // JoinError, then task error

// Bounded concurrency over a stream of work
use futures::{stream, StreamExt};
let results: Vec<_> = stream::iter(items).map(|i| process(i)).buffer_unordered(16).collect().await;

// Graceful shutdown
let token = tokio_util::sync::CancellationToken::new();
let worker = tokio::spawn(run(token.child_token()));
tokio::signal::ctrl_c().await?;
token.cancel();
tokio::time::timeout(Duration::from_secs(10), worker).await??;

// Inside a worker
loop {
    tokio::select! {
        _ = token.cancelled() => break,
        Some(msg) = rx.recv() => handle(msg).await?,
    }
}
```

- Channels: `mpsc` (work queue), `oneshot` (reply), `broadcast` (fan-out; lagging receivers
  get `RecvError::Lagged`), `watch` (latest value / config reload).
- Shared state: `Arc<T>` of immutable config; `Arc<Mutex<T>>` (std) for short critical
  sections; an actor task owning the state + `mpsc` for complex state machines.
- Async closures *(1.85)* and `AsyncFn*` bounds replace `F: Fn() -> Fut, Fut: Future`.
- Streams: `futures::Stream` + `StreamExt`, or `tokio_stream`. Sinks/framing:
  `tokio_util::codec::{Framed, LengthDelimitedCodec, LinesCodec}`.
- I/O: `AsyncReadExt`/`AsyncWriteExt` (`read_buf`, `write_all`); `BufReader`/`BufWriter` and
  `flush().await` before dropping writers; `TcpStream::into_split()` for concurrent
  read/write halves.

## Ecosystem defaults (check the lockfile before assuming versions)

| Need | Crate |
|---|---|
| HTTP server | `axum` (on `hyper` 1 + `tower`) |
| HTTP client | `reqwest` (use `rustls` features to avoid OpenSSL), `hyper-util` for low level |
| gRPC | `tonic` + `prost` |
| TLS | `rustls` + `tokio-rustls`; `rustls-platform-verifier` for OS roots |
| Middleware/timeouts/retries | `tower`, `tower-http` |
| Tracing | `tracing` + `tracing-subscriber`; `#[tracing::instrument(skip(big_arg))]` |
| DB | `sqlx` (compile-time-checked SQL, parameterized), `tokio-postgres`, `deadpool`/`bb8` pools |

Never build SQL with `format!`; use bind parameters (`sqlx::query!("… WHERE id = $1", id)`).

## Debugging async

- `tokio-console` (needs `console-subscriber` + `--cfg tokio_unstable`) for stuck tasks.
- Hangs: look for a lock held across await, a full bounded channel nobody drains, a
  `JoinHandle` awaited before the task's input is sent, or blocking code on a worker.
- Tests: `#[tokio::test]` (current-thread), `#[tokio::test(flavor = "multi_thread")]` for
  `spawn_blocking`/`block_in_place`; `tokio::time::pause()` + `advance()` for timer logic
  (needs the `test-util` feature).
