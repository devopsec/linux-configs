# Testing & debugging

## Quality gates (run before reporting done)

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --locked -- -W clippy::pedantic   # template `just check` uses --all-features
cargo test --locked
cargo build --release --locked
```

`scripts/validate-project.sh` runs these plus metadata checks. If the project forwards platform
features (`wayland`, `wgpu`, `dbus-config`), also try `cargo check --no-default-features` to catch
cfg-gated breakage (libcosmic itself checks `wayland` and `winit` separately).

## What to unit-test

UI rendering isn't unit-testable in practice; structure code so logic is:
- `update()` transitions: construct the model with `cosmic::Core::default()` (if `Default` is derivable
  at the pinned rev) or test the pure functions `update` delegates to.
- Config (de)serialisation and version migration (`cosmic-files/src/config.rs` has tests).
- Parsers, file operations, D-Bus payload mapping — keep them out of `app.rs`.
Use `#[tokio::test]` for async helpers.

## Running & logs

| Goal | How |
|---|---|
| Run app | `just run` (`RUST_BACKTRACE=full cargo run --release`) |
| Verbose logs | `RUST_LOG=debug` (libcosmic logs via `tracing`; add `tracing-subscriber`/`env_logger` init in `main` if the app has none) |
| Wayland traffic | `WAYLAND_DEBUG=1 <bin> 2>wayland.log` |
| XWayland? | `xprop` can't select native Wayland windows |
| Skip single-instance | `COSMIC_SINGLE_INSTANCE=0 <bin>` |
| Session components | `journalctl --user -f` (cosmic-comp, cosmic-panel, applets log to journald) |
| Config state | `ls ~/.config/cosmic/<APP_ID>/v1/` — RON per field; delete a file to reset that field |
| D-Bus | `busctl --user monitor <name>`; `dbus-monitor --session` |
| GPU | `eglinfo`, `vulkaninfo`; force software path by building without `wgpu` |
| Profiling | `perf top -p $(pidof <bin>)`; build with `--profile release-with-debug` if defined |
| Frozen desktop | switch TTY / SSH in, `pidof cosmic-comp`, attach `gdb` (see `cosmic-epoch/docs/DEBUGGING.md`) |

## Common build failures

| Symptom | Cause / fix |
|---|---|
| `the lock file needs to be updated but --locked was passed` | No/old `Cargo.lock` — `cargo generate-lockfile` (or `cargo update -p libcosmic`) |
| `pkg-config` / `xkbcommon` / `fontconfig` / `freetype` not found | Missing system headers — `scripts/check-env.sh` prints distro packages |
| `rustc X is not supported by … libcosmic` / edition 2024 errors | Toolchain older than libcosmic `rust-version` — `rustup update` or add `rust-toolchain.toml` |
| `expected Task<Action<Message>>, found Task<Message>` | `.map(cosmic::Action::App)` or use `cosmic::task::*` helpers |
| `no function or associated item named … found` after `cargo update` | libcosmic API moved — `scripts/upstream.sh pin` + `grep` for the new name in examples/official apps |
| Unresolved import under `cosmic::iced::platform_specific` | `wayland` feature disabled |
| `dialog` / `file_chooser` missing | enable `xdg-portal` (or `rfd`) |
| `about` / `single-instance` / `applet` items missing | corresponding libcosmic feature not enabled |
| Two async runtimes conflict | `tokio` and `smol` features both on — pick one |

## Runtime checklist (manual, in a COSMIC session)

- Light ↔ dark switch (Settings → Appearance) restyles live; accent colour respected.
- Window resizes down to `size_limits` min without clipped controls; nav bar collapses on narrow widths.
- Keyboard: Tab focus order, shortcuts shown in menus actually fire, Esc closes dialogs/drawers.
- Second launch focuses existing window (if single-instance).
- Applets: horizontal and vertical panel, sizes XS–XL, popup opens/closes repeatedly, overflow behaviour.
- Fresh config dir (move `~/.config/cosmic/<APP_ID>` aside) starts with sane defaults.
