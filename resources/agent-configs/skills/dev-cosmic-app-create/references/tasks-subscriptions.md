# Tasks, subscriptions & async

`update()` and `view()` run on the UI thread — anything slower than a state mutation belongs in a Task
(one-shot/finite) or a Subscription (lives as long as it is returned from `subscription()`).

## Tasks (`cosmic::task`)

```rust
fn update(&mut self, message: Message) -> cosmic::Task<cosmic::Action<Message>> {
    match message {
        Message::Load(path) => {
            return cosmic::task::future(async move {
                Message::Loaded(tokio::fs::read_to_string(path).await.map_err(Arc::new))
            });
        }
        Message::Loaded(result) => { self.content = result; }
    }
    cosmic::Task::none()
}
```

| Helper | Meaning |
|---|---|
| `cosmic::task::future(fut)` | Run future, emit its output (`Into<Message>`) |
| `cosmic::task::message(msg)` | Emit a message immediately |
| `cosmic::task::batch(vec![..])` | Run concurrently, messages in completion order |
| `cosmic::task::stream(stream)` | Emit every item of a `Stream` |
| `cosmic::task::none()` / `Task::none()` | Nothing |
| `task.chain(other)` | Sequential |
| `let (task, handle) = task.abortable()` | Store `handle`, call `handle.abort()` to cancel |
| `Task::stream(cosmic::iced::stream::channel(n, \|mut tx\| async move { tx.send(..).await; }))` | Generator-style progress |

- Errors in messages must be `Clone` → wrap in `Arc<E>` or convert to `String`.
- Default executor is single-threaded tokio: wrap CPU-bound/blocking calls in
  `tokio::task::spawn_blocking`.
- Raw iced tasks need `.map(cosmic::Action::App)`; runtime actions use `cosmic::Action::Cosmic(..)` via
  `cosmic::command::*` helpers or `ApplicationExt` methods.

## Subscriptions

```rust
fn subscription(&self) -> Subscription<Message> {
    let mut subs = vec![
        self.core().watch_config::<Config>(Self::APP_ID)
            .map(|update| Message::UpdateConfig(update.config)),
    ];
    if self.ticking {
        subs.push(Subscription::run(|| {
            cosmic::iced::stream::channel(1, |mut tx: futures::channel::mpsc::Sender<_>| async move {
                let mut iv = tokio::time::interval(Duration::from_secs(1));
                loop { iv.tick().await; _ = tx.send(Message::Tick).await; }
            })
        }));
    }
    Subscription::batch(subs)
}
```

- Identity: `Subscription::run(fn)` is keyed by the function pointer; for parameterised streams use
  `Subscription::run_with(data, |data| stream)` — `data: Hash` is the identity (official apps pass
  `TypeId::of::<Marker>()` or `(TypeId, path)`; see `cosmic-edit` `WatcherSubscription`,
  `cosmic-files/src/tab.rs`). Changing `data` restarts the stream. Older iced revs used
  `run_with_id(id, stream)` — if it doesn't compile, grep the pinned rev.
- Conditional subscriptions start/stop by being added/removed from the batch.
- A channel future that returns ends the subscription; end with `futures::future::pending().await` if it
  must stay alive after sending.
- Keyboard/window events: `cosmic::iced::event::listen_with(|event, status, window_id| …)`;
  timers: `cosmic::iced::time::every(Duration)`.
- Config/state: `core.watch_config::<T>(APP_ID)` / `watch_state::<T>(APP_ID)`; system theme changes are
  delivered through `system_theme_update` hooks — no subscription needed.

## D-Bus from tasks

Use `zbus` (already a libcosmic dependency with the tokio feature). Create proxies inside
`cosmic::task::future` or a subscription; never use `zbus::blocking` on the UI thread. For signals,
turn `proxy.receive_*().await` streams into a `Subscription::run_with` channel.
