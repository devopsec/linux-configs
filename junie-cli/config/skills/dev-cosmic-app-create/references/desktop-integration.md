# Desktop integration

## Contents
- [Identity: one App ID everywhere](#identity-one-app-id-everywhere)
- [Configuration (cosmic-config)](#configuration-cosmic-config)
- [Theming](#theming)
- [Localization (i18n)](#localization-i18n)
- [Desktop entry](#desktop-entry)
- [AppStream metainfo](#appstream-metainfo)
- [Icons](#icons)
- [D-Bus, portals, notifications](#d-bus-portals-notifications)

## Identity: one App ID everywhere

The RDNN App ID must be identical in: `const APP_ID` (Rust), justfile `appid`, desktop file name
`<APP_ID>.desktop`, `Icon=<APP_ID>`, metainfo `<id>` + `<launchable type="desktop-id"><APP_ID>.desktop`,
installed icon `<APP_ID>.svg`, Flatpak `id`, cosmic-config directory, D-Bus name (single-instance).
`scripts/validate-project.sh` checks the first five.

## Configuration (cosmic-config)

```rust
use cosmic::cosmic_config::{self, CosmicConfigEntry, cosmic_config_derive::CosmicConfigEntry};

#[derive(Debug, Default, Clone, CosmicConfigEntry, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
#[version = 1]
pub struct Config { pub show_hidden: bool, pub app_theme: AppTheme }
```

- Storage: one RON file per field at `$XDG_CONFIG_HOME/cosmic/<APP_ID>/v<version>/<field>`; system
  defaults read from `$XDG_DATA_DIRS/cosmic/<APP_ID>/v<version>/<field>` (e.g. `/usr/share/cosmic/…`).
  In Flatpak it uses `HOST_XDG_CONFIG_HOME` → needs a `xdg-config/cosmic…` filesystem permission.
- Load: `cosmic_config::Config::new(APP_ID, Config::VERSION)` → `Config::get_entry(&handler)` returns
  `Ok(cfg)` or `Err((errors, cfg_with_defaults))` — log errors, keep defaults. Keep the handler
  (`Option<cosmic_config::Config>`) in the model.
- Write: derive generates `cfg.set_<field>(&handler, value) -> Result<bool, _>` (writes only on change).
  Batch writes: `handler.transaction()`.
- Watch: `self.core().watch_config::<Config>(APP_ID)` subscription → `Message::UpdateConfig(update.config)`.
- Ephemeral state (window size, recent files): `cosmic_config::Config::new_state` + `watch_state`
  (`~/.local/state/cosmic/<APP_ID>/…`).
- Bump `#[version]` on incompatible changes; v(N) falls back to v(N-1) on first read.
- Feature `dbus-config` routes watches through `cosmic-settings-daemon` (needs D-Bus name
  `com.system76.CosmicSettingsDaemon` in Flatpak).

## Theming

- Never hard-code colours; use style classes via `.class(..)` (`cosmic::theme::Button::Suggested`,
  `theme::Container::Card`, `theme::Container::custom(fn)`, …) and `theme::active().cosmic()` for palette/spacing/corner radii when drawing custom widgets.
- App-level light/dark override (pattern from `cosmic-edit/src/config.rs`):
  `enum AppTheme { Dark, Light, System }` → `theme::system_dark()` / `theme::system_light()` /
  `theme::system_preference()`; apply with `cosmic::command::set_theme(theme)` on startup and config change.
- React to system changes via `system_theme_update` / `system_theme_mode_update` hooks if the app caches
  anything theme-derived.
- Respect accent colour, corner radii, and high-contrast (the toolkit does this automatically for stock widgets).

## Localization (i18n)

- Fluent files: `i18n/<lang>/<crate_snake_name>.ftl`; `i18n.toml` sets `fallback_language = "en"`.
- `fl!("message-id")` / `fl!("page-id", num = 1)` via the template's `src/i18n.rs`; call `i18n::init` in `main`.
- Template `build.rs` uses `xdgen` to expand `resources/app.desktop` + `app.metainfo.xml` into
  `target/xdgen/` with translated `app-title`, `app-comment`, `app-keywords` from the `.ftl` files —
  **install the generated files**, not the sources (template justfile does).
- All user-visible strings go through `fl!`; icon names in desktop files must not be translated.

## Desktop entry

App (template):
```ini
[Desktop Entry]
Name=My App
Comment=…
Type=Application
Icon=io.github.user.MyApp
Exec=cosmic-ext-my-app %F
Terminal=false
StartupNotify=true
Categories=COSMIC
Keywords=COSMIC
MimeType=
```
Add a real freedesktop main category (`Utility;`, `Development;`, `Graphics;`…) for menus outside
COSMIC; terminate lists with `;`. `DBusActivatable=true` only with an installed
`share/dbus-1/services/<APP_ID>.service`. Applet keys: [applet.md](applet.md#desktop-entry-keys-read-by-cosmic-panel--cosmic-settings).
Validate: `desktop-file-validate target/xdgen/app.desktop`.

## AppStream metainfo

Template fields: `<id>`, `metadata_license` (CC0-1.0), `project_license`, `name`, `summary`, `icon`,
`url type="vcs-browser"`, `launchable`, `provides` (`<id>com.system76.CosmicApplication</id>` or
`com.system76.CosmicApplet` + `<binaries>`), `requires display_length`, `supports control`,
`categories`, `keywords`, `content_rating oars-1.1`. For Flathub/COSMIC Store also add `<description>`,
`<developer id=…><name>`, `<releases>` (newest first), `<screenshots>`, `<url type="homepage">`,
`<branding>` colours. Install to `share/metainfo/<APP_ID>.metainfo.xml` (template justfile uses the
legacy `share/appdata/` — prefer `metainfo/`). Validate: `appstreamcli validate --no-net <file>`
(Flathub additionally runs `flatpak-builder-lint appstream`).

## Icons

- App icon: scalable SVG installed as `share/icons/hicolor/scalable/apps/<APP_ID>.svg`.
- Applet panel icon: symbolic `<APP_ID>-symbolic.svg` in the same dir; reference with
  `icon_button("<APP_ID>-symbolic")`.
- In-app icons: `icon::from_name("…-symbolic")` resolves from the COSMIC icon theme (bundled in
  Flatpak via `com.system76.Cosmic.BaseApp`).

## D-Bus, portals, notifications

- **D-Bus**: `zbus` async proxies inside tasks/subscriptions (see [tasks-subscriptions.md](tasks-subscriptions.md#d-bus-from-tasks)).
  Inspect services with `busctl --user list`, `busctl --user introspect <name> <path>`.
  Every name used must appear as `--talk-name` / `--system-talk-name` in Flatpak.
- **Portals**: feature `xdg-portal` pulls `ashpd`; file chooser via `cosmic::dialog::file_chooser`.
  Other portals (screenshot, open URI, background, camera…) via `ashpd` directly. Check which the
  COSMIC portal backend implements: `/usr/share/xdg-desktop-portal/portals/cosmic.portal` and
  `pop-os/xdg-desktop-portal-cosmic`.
- **Open URLs/files**: `open::that_detached(url)` (template), or the OpenURI portal inside Flatpak.
- **Launch desktop apps**: libcosmic feature `desktop` (`cosmic::desktop`), `desktop-systemd-scope`
  to launch inside systemd scopes.
- **Notifications**: `notify-rust` (as `cosmic-store` feature `notify`) → `org.freedesktop.Notifications`
  (Flatpak: `--talk-name=org.freedesktop.Notifications`), or the Notification portal.
- **Wayland**: libcosmic uses `cctk` (cosmic-client-toolkit) for COSMIC protocols (workspaces, toplevel
  info, screencopy). Only reach for `cosmic::cctk` when the toolkit lacks a feature; reference
  `cosmic-applets`/`cosmic-workspaces-epoch`.
