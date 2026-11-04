# Upstream sources & version discovery

Snapshot notes verified against upstream in 2026-10 (libcosmic `95236a9`, templates `97ff759`/`58f506f`).
Re-verify anything version-sensitive with `scripts/upstream.sh`.

## Authority ladder

| Rank | Source | Use for |
|---|---|---|
| 1 | Project `Cargo.lock` → libcosmic commit | Which API actually compiles |
| 2 | [pop-os/libcosmic](https://github.com/pop-os/libcosmic) `src/`, `examples/` at that commit | Signatures, features, widget builders |
| 3 | [cosmic-app-template](https://github.com/pop-os/cosmic-app-template), [cosmic-applet-template](https://github.com/pop-os/cosmic-applet-template) | Project layout, justfile, desktop/metainfo, i18n, config |
| 4 | Official apps (table below) | Real-world patterns for a given feature |
| 5 | [API docs](https://pop-os.github.io/libcosmic/cosmic/) | Browsing (built from libcosmic master, may be ahead of your pin) |
| 6 | [libcosmic book](https://pop-os.github.io/libcosmic-book/) | Concepts (MVU, tasks, nav/menu/context drawer, applets) — code is partly stale |

Known stale spots in the book (2026-10): subscriptions chapter uses
`cosmic::subscription::channel(TypeId, …)` (current: `Subscription::run(|| cosmic::iced::stream::channel(n, |tx| async move {…}))`);
applet chapter's `style()` returns `cosmic::iced_runtime::Appearance` (current: `Option<cosmic::iced::theme::Style>`);
`Command::none()` in examples (current: `Task::none()`).

## libcosmic facts (verify per pin)

- Crate `libcosmic`, imported as `cosmic`; git dependency only (`git = "https://github.com/pop-os/libcosmic.git"`).
  `version = "1.0.0"`, `edition = "2024"`, `rust-version = "1.93"` at the snapshot. Official apps pin
  1.93–1.95 via `rust-toolchain.toml`.
- Default features: `winit, tokio, a11y, dbus-config, x11, wayland, multi-window`.
- Notable features: `about`, `applet`, `applet-token`, `single-instance`, `xdg-portal` (ashpd dialogs),
  `rfd`, `desktop` (+`desktop-systemd-scope`), `wgpu` (else softbuffer), `markdown`, `qr_code`,
  `highlighter`, `animated-image`, `process`, `surface-message`, `autosize`, `advanced-shaping`, `debug`.
  `tokio`/`smol`/`async-std` are mutually exclusive runtimes.
- Official apps use `default-features = false` + explicit list, then forward platform toggles as their own
  Cargo features so non-Linux/X11 builds stay possible:

  ```toml
  [dependencies.libcosmic]
  git = "https://github.com/pop-os/libcosmic.git"
  default-features = false
  features = ["about", "multi-window", "tokio", "winit", "surface-message"]

  [features]
  default = ["dbus-config", "wgpu", "wayland"]
  dbus-config = ["libcosmic/dbus-config"]
  wgpu = ["libcosmic/wgpu"]
  wayland = ["libcosmic/wayland"]
  ```

- To test a local libcosmic checkout, the templates ship a commented `[patch.'https://github.com/pop-os/libcosmic']`
  block patching `libcosmic`, `cosmic-config`, `cosmic-theme`.
- Updating: `cargo update -p libcosmic` moves to latest master — expect breaking changes; rebuild and
  re-grep any API that fails.

## System build dependencies

From libcosmic README (Debian/Pop names): `cargo cmake just libexpat1-dev libfontconfig-dev
libfreetype-dev libxkbcommon-dev pkgconf`. Fedora: `cmake just expat-devel fontconfig-devel
freetype-devel libxkbcommon-devel pkgconf-pkg-config`. Arch: `cmake just expat fontconfig freetype2
libxkbcommon pkgconf`. Scaffolding needs `cargo install cargo-generate`.

## Official repos worth grepping

| Repo | Study for |
|---|---|
| `libcosmic/examples/*` | `application`, `applet`, `config`, `context-menu`, `menu`, `multi-window`, `nav-context`, `open-dialog`, `table-view`, `text-input`, `subscriptions`, `calendar`, `about`… (`just run <name>`) |
| `cosmic-edit` | Small, idiomatic app: config + `AppTheme`, menus, key binds, tabs, dialogs, i18n |
| `cosmic-files` | Large app: dialogs, multi-window, DnD, thumbnails, unit tests |
| `cosmic-store` | `single-instance` + `CosmicFlags` + `dbus_activation`, notifications, Flatpak backend |
| `cosmic-term` | Custom widget rendering, tests |
| `cosmic-settings` | Workspace layout, page abstraction, settings widgets, many D-Bus clients |
| `cosmic-applets` | Every built-in applet: popups, `X-Cosmic*` desktop keys, D-Bus/system integration |
| `cosmic-panel` | Panel config schema (`data/default_schema`), how applets are launched |
| `cosmic-epoch` | Component inventory (README), `TRADEMARK.md`, `docs/DEBUGGING.md` |
| `cosmic-flatpak` | Applet manifests (`app/<id>/<id>.json`) and build justfile |
| `xdg-desktop-portal-cosmic` | Which portals COSMIC implements |

Community apps: <https://github.com/cosmic-utils> (many Flathub-published `cosmic-ext-*` projects).

## Naming & trademark (TRADEMARK.md §5)

- Official software: `cosmic-` package namespace + `com.system76.` App IDs. **Third parties must not use them.**
- Third party: `cosmic-ext-<name>` package/binary, own RDNN App ID (e.g. `io.github.<user>.<Name>`),
  described as "for the COSMIC™ desktop". Inclusion as official: contact cosmic@system76.com.
- App template App ID regex (Flathub-compatible): lowercase segments except the last, `-` → `_` in
  non-final segments, 3–5 segments.

## Community

Mattermost: <https://chat.pop-os.org/> (`pop-os/channels/development`, `cosmic-epoch`). Issues on the
relevant `pop-os/*` repo.
