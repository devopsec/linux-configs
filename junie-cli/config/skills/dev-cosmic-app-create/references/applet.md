# COSMIC panel/dock applets

Applets are ordinary libcosmic `Application`s run in a transparent, headerless surface hosted by
`cosmic-panel` (itself a nested Wayland compositor). Popups are forwarded to the host compositor.
Verified against `cosmic-applet-template` `58f506f`, libcosmic `src/applet/mod.rs`, `cosmic-applets`,
`cosmic-panel` (2026-10).

## Differences from an app

| Aspect | App | Applet |
|---|---|---|
| Entry | `cosmic::app::run::<App>(settings, flags)` | `cosmic::applet::run::<App>(flags)` (settings derived from panel) |
| libcosmic features | per app (`about`, `wgpu`, `xdg-portal`, …) | `applet`, `applet-token`, `dbus-config`, `multi-window`, `tokio`, `wayland`, `winit`; drop `wgpu` for lower RAM unless needed |
| `view()` | Main window | The panel button only |
| Popup | — | `view_window(id)` + `get_popup`/`destroy_popup` |
| `style()` | default | `Some(cosmic::applet::style())` (transparent) |
| Desktop entry | visible launcher | `NoDisplay=true`, `X-CosmicApplet=true`, `X-CosmicHoverPopup=Auto` (+ optional keys) |
| Metainfo `provides` | `com.system76.CosmicApplication` | `com.system76.CosmicApplet` |
| Distribution | Flathub | COSMIC Flatpak repo only (Flathub forbids desktop-specific components) |

## Core pattern (template)

```rust
#[derive(Default)]
pub struct AppModel { core: cosmic::Core, popup: Option<Id>, config: Config }

fn view(&self) -> Element<'_, Message> {
    self.core.applet.icon_button("display-symbolic").on_press(Message::TogglePopup).into()
}

fn view_window(&self, _id: Id) -> Element<'_, Message> {
    let content = widget::list_column().add(widget::settings::item(label, widget::toggler(v).on_toggle(Message::Toggle)));
    self.core.applet.popup_container(content).into()
}

// in update():
Message::TogglePopup => return if let Some(p) = self.popup.take() {
    destroy_popup(p)
} else {
    let new_id = Id::unique();
    self.popup.replace(new_id);
    let mut s = self.core.applet.get_popup_settings(self.core.main_window_id().unwrap(), new_id, None, None, None);
    s.positioner.size_limits = Limits::NONE.max_width(372.0).min_width(300.0).min_height(200.0).max_height(1080.0);
    get_popup(s)
},
Message::PopupClosed(id) => if self.popup == Some(id) { self.popup = None; },

fn on_close_requested(&self, id: Id) -> Option<Message> { Some(Message::PopupClosed(id)) }
fn style(&self) -> Option<cosmic::iced::theme::Style> { Some(cosmic::applet::style()) }
```

Imports: `cosmic::iced::platform_specific::shell::wayland::commands::popup::{destroy_popup, get_popup}`,
`cosmic::iced::{window::Id, Limits}`.

`self.core.applet` (`cosmic::applet::Context`) helpers: `icon_button`, `icon_button_from_handle`,
`text_button`, `button_from_element`, `applet_tooltip`, `popup_container`, `get_popup_settings`,
`autosize_window`, `suggested_size(is_symbolic)`, `suggested_padding`, `is_horizontal()` (panel
orientation), `theme()`, `text()`. Free functions: `cosmic::applet::{menu_button, padded_control, menu_control_padding}`
for popup menu rows (see `cosmic-applet-power`).

Always respect `is_horizontal()` and `suggested_size()` — panels can be vertical and any size (XS–XL).

## Desktop entry keys (read by cosmic-panel / cosmic-settings)

| Key | Values | Meaning |
|---|---|---|
| `X-CosmicApplet` | `true` | Listed in Settings → Desktop → Panel/Dock → Applets (required) |
| `NoDisplay` | `true` | Hide from app launchers (required) |
| `X-CosmicHoverPopup` | `Auto` \| `Start` \| `End` | Popup anchoring when hovering between applets |
| `X-CosmicShrinkable` | `true` | Applet may shrink when panel space is tight |
| `X-OverflowPriority` | int (built-ins 5–100) | Higher stays visible longer before overflow |
| `X-OverflowMinSize` | int | Minimum items before overflowing (multi-item applets) |

The panel launches applets by **desktop entry ID** (= App ID = file stem). Its config stores them in
`~/.config/cosmic/com.system76.CosmicPanel.<Panel|Dock>/v1/plugins_wings` / `plugins_center`
(RON, e.g. `Some(["com.system76.CosmicAppletTime"])`).

## Local testing

1. `cargo build --release` then install to user prefix: `just prefix="$HOME/.local" install`
   (template justfile; `base-dir` = `rootdir/prefix`). Panel discovers entries via XDG data dirs
   including `~/.local/share/applications`.
2. Ensure `~/.local/bin` is on the **session** `PATH` (the entry uses a bare `Exec=<name>`), or install
   system-wide with `sudo just install` (ask the user first).
3. Settings → Desktop → Panel → Applets → Add applet. Changes to the binary need the applet process
   restarted: `pkill -f <binary>` (panel respawns it) or remove/re-add the applet.
4. Logs: applet stderr goes to the journal via cosmic-panel: `journalctl --user -f | grep <binary>`
   (or `journalctl --user -t cosmic-panel`). Use `RUST_LOG=debug` by temporarily changing `Exec=`.
5. Running the binary directly outside the panel won't render correctly — only use it for crash checks.

## Pitfalls

- Template `justfile` `vendor` recipe (2026-10) deletes `vendor` without creating `vendor.tar`, breaking
  `build-vendored`; copy the app template's `vendor` recipe if vendoring.
- Forgetting `on_close_requested` → stale `popup` id, next click does nothing.
- Heavy work in `view()` — applets redraw with the panel; precompute.
- Hard-coded pixel sizes instead of `suggested_size()`.
- Using `cosmic::app::run` for an applet → normal decorated window.
