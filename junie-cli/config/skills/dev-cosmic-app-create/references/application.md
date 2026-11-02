# COSMIC applications (libcosmic)

Patterns from libcosmic `src/app/mod.rs`, `cosmic-app-template`, and official apps (2026-10). Signatures
drift — confirm with `scripts/upstream.sh grep` against the pinned rev.

## Contents
- [Project layout](#project-layout)
- [Entry point](#entry-point)
- [The Application trait](#the-application-trait)
- [COSMIC shell concepts](#cosmic-shell-concepts)
- [Widgets & layout](#widgets--layout)
- [Single instance & CLI flags](#single-instance--cli-flags)
- [Multi-window](#multi-window)
- [Common pitfalls](#common-pitfalls)

## Project layout

```
Cargo.toml  build.rs (xdgen → target/xdgen/app.desktop, app.metainfo.xml)
justfile    i18n.toml  i18n/en/<crate_snake>.ftl
resources/  app.desktop  app.metainfo.xml  icons/hicolor/scalable/apps/icon.svg
src/main.rs  (i18n init, Settings, run)
src/app.rs   (AppModel + impl cosmic::Application)
src/config.rs (CosmicConfigEntry)
src/i18n.rs  (fl! macro over i18n-embed + rust-embed)
```

Split large apps into modules each with its own `Message`, `update`, `view` (see book "Modules"), mapping
child messages into the parent enum. Keep the `Message` type uniform across views to limit
monomorphization (book "Reducing Monomorphization").

## Entry point

```rust
fn main() -> cosmic::iced::Result {
    let requested = i18n_embed::DesktopLanguageRequester::requested_languages();
    i18n::init(&requested);
    let settings = cosmic::app::Settings::default()
        .size_limits(cosmic::iced::Limits::NONE.min_width(360.0).min_height(180.0));
    cosmic::app::run::<app::AppModel>(settings, ())
}
```

`Settings` is a builder (`.size(..)`, `.size_limits(..)`, `.theme(..)`, `.client_decorations(..)`,
`.exit_on_close(..)`, `.no_main_window(..)`, `.transparent(..)`, `.debug(..)`, `.default_icon_theme(..)`).

## The Application trait

Required: `type Executor` (`cosmic::executor::Default`), `type Flags`, `type Message: Clone + Debug + Send + 'static`,
`const APP_ID: &'static str` (RDNN; must equal desktop file stem, metainfo `<id>`, justfile `appid`),
`core()/core_mut()` returning the stored `cosmic::Core`, `init(core, flags) -> (Self, Task<Action<Message>>)`,
`view(&self) -> Element<'_, Message>`.

Optional hooks (defaults are no-ops):

| Method | Use |
|---|---|
| `update(&mut self, msg) -> Task<cosmic::Action<Message>>` | State transitions; return tasks for async work |
| `subscription(&self) -> Subscription<Message>` | Long-lived event sources (config watch, timers, D-Bus) |
| `header_start/center/end(&self) -> Vec<Element>` | Header bar content (menu bar goes in `header_start`) |
| `nav_model(&self) -> Option<&nav_bar::Model>` + `on_nav_select(id)` | Sidebar navigation |
| `context_drawer(&self) -> Option<ContextDrawer>` | Right-side drawer (About, settings, details) |
| `dialog(&self) -> Option<Element>` | Modal dialog overlay (`widget::dialog()`) |
| `footer(&self)` | Bottom bar |
| `view_window(&self, id)` | Views for extra windows/popups |
| `on_escape`, `on_search`, `on_close_requested(id)`, `on_app_exit`, `on_window_resize`, `on_context_drawer` | Lifecycle hooks |
| `system_theme_update`, `system_theme_mode_update` | React to theme changes |
| `dbus_activation(msg)` | Single-instance activations (feature `single-instance`) |
| `style(&self) -> Option<cosmic::iced::theme::Style>` | Window style override (applets) |

`ApplicationExt` (in `cosmic::prelude::*`) adds `set_window_title(title, id)`, `set_header_title`,
`watch_config::<T>(app_id)`, `watch_state::<T>(app_id)`, `drag/maximize/minimize`.

### Task & Action types

All `Task`s returned to the runtime are `Task<cosmic::Action<Message>>`. Convert app messages with
`cosmic::task::message(m)`, `cosmic::task::future(async { … Message::Done })`,
`cosmic::task::batch(vec![…])`, `.map(cosmic::Action::App)` for raw iced tasks, or
`cosmic::Action::from`. Runtime commands live in `cosmic::command::*` (`set_theme`, `set_title`,
`maximize`, `toggle_maximize`, …). Details: [tasks-subscriptions.md](tasks-subscriptions.md).

## COSMIC shell concepts

- **Nav bar**: `nav_bar::Model::default()`, `.insert().text(..).icon(icon::from_name("…-symbolic")).data::<Page>(…).activate()`;
  read with `self.nav.active_data::<Page>()`. Return it from `nav_model()`; handle `on_nav_select` by
  `self.nav.activate(id)` then updating the title.
- **Menu bar**: `menu::bar(vec![menu::Tree::with_children(menu::root(label).apply(Element::from), menu::items(&self.key_binds, vec![menu::Item::Button(label, icon_opt, Action)]))])`.
  Implement `menu::action::MenuAction for Action { type Message; fn message(&self) -> Message }`.
  `HashMap<KeyBind, Action>` only **labels** shortcuts in menus — actually handling them requires a
  keyboard subscription (`cosmic::iced::event::listen_with`) that checks `KeyBind::matches` (see
  `cosmic-edit/src/key_bind.rs` + its `subscription()`).
- **Context drawer**: toggle `self.core.window.show_context`; return
  `context_drawer::about(&self.about, |url| Message::LaunchUrl(..), Message::ToggleContextPage(..))` or
  `context_drawer::context_drawer(content, on_close).title(..).actions(..).footer(..)`.
- **About**: feature `about`; `widget::about::About::default().name(..).icon(..).version(..).links([..]).license(..)`.
- **Dialogs (in-app)**: `widget::dialog().title(..).body(..).control(..).primary_action(button::suggested(..)).secondary_action(button::standard(..))`
  returned from `dialog()`; keep an `Option<DialogPage>` in the model.
- **File chooser**: feature `xdg-portal` (or `rfd`); `cosmic::dialog::file_chooser::open::Dialog::new().title(..).filter(FileFilter)`, then `.open_file().await` inside `cosmic::task::future`; handle `file_chooser::Error::Cancelled`. Pattern: `libcosmic/examples/open-dialog`.
- **Toasts**: `widget::toaster` + `widget::toaster::Toasts` stored in the model.

## Widgets & layout

- Use `cosmic::widget::{button, text, text_input, toggler, dropdown, spin_button, segmented_button, settings, list_column, column, row, container, scrollable, icon, popover, menu, table, calendar, color_picker}`.
- Text roles: `widget::text::{title1..title4, heading, body, caption, monotext}` — don't hand-size fonts.
- Buttons: `button::{standard, suggested, destructive, text, icon, link}`.
- Settings-style pages: `widget::settings::section().title(..).add(settings::item(label, control))`
  (or `item::builder(label).control(..)`).
- Spacing from theme, not literals: `cosmic::theme::spacing().space_s` (or
  `self.core().system_theme().cosmic().spacing`). Fields: `space_none, space_xxxs … space_xxxl`.
- Icons: `icon::from_name("name-symbolic")` (follows system icon theme); bundle app icon via
  `icon::from_svg_bytes(include_bytes!(..))`.
- `.apply(widget::container)` / `.apply(Element::from)` from `cosmic::Apply` for fluent wrapping.

## Single instance & CLI flags

Feature `single-instance` + `cosmic::app::run_single_instance::<App>(settings, flags)` (note: the app
template enables the feature but still calls `run`). Flags must implement `cosmic::app::CosmicFlags`
(`type SubCommand`, `type Args`, `fn action()`). Handle re-activation in `dbus_activation(msg)` —
open a window if none (`core.main_window_id().is_none()`), act on `Details::ActivateAction { action, .. }`.
Set `DBusActivatable=true` in the desktop file only if a matching D-Bus service file is installed.
`COSMIC_SINGLE_INSTANCE=0` disables it for debugging. Reference: `cosmic-store/src/main.rs`.

## Multi-window

Feature `multi-window`; open with `cosmic::iced::window::open(window::Settings{..})` → `(id, task)`; render
in `view_window(id)`; track ids in the model; close via `window::close(id)`; handle `on_close_requested`.
`Settings::no_main_window(true)` for daemon-style apps that open windows on demand.

## Common pitfalls

- App template hard-codes `APP_ID = "dev.mmurphy.Test"` (2026-10) — replace with your RDNN ID
  (`scaffold.sh` does this).
- Returning `Task<Message>` instead of `Task<cosmic::Action<Message>>` → type error; map with `cosmic::Action::App`.
- Blocking I/O in `update`/`view` freezes the UI; the default executor is single-threaded tokio — use
  `tokio::task::spawn_blocking` for CPU-bound work inside tasks.
- Doing work in `view()` — it runs every frame-ish; precompute in `update`.
- `nav.active_data::<Page>().unwrap()` panics if nothing is active — always `.activate()` one item.
- Copying iced (upstream) examples verbatim: libcosmic uses a pop-os iced fork; check the re-export
  `cosmic::iced::*` for the actual API.
