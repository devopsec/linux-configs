# Packaging & distribution

Verified against `cosmic-flatpak`, Flathub repos `com.system76.Cosmic.BaseApp`,
`dev.edfloreshz.CosmicTweaks`, `io.github.cosmic_utils.Examine`, `io.github.cosmic_utils.camera`,
and `flatpak-builder-tools` (2026-10). Runtime versions move yearly — re-check before publishing.

## Contents
- [Channels](#channels)
- [Native install (justfile)](#native-install-justfile)
- [Flatpak: app (Flathub)](#flatpak-app-flathub)
- [Flatpak: applet (COSMIC Flatpak repo)](#flatpak-applet-cosmic-flatpak-repo)
- [finish-args guidance](#finish-args-guidance)
- [Generating cargo-sources.json](#generating-cargo-sourcesjson)
- [Build, lint, test locally](#build-lint-test-locally)

## Channels

| Kind | Channel | Notes |
|---|---|---|
| App | [Flathub](https://docs.flathub.org/docs/for-app-authors/submission) | Metainfo `provides` `com.system76.CosmicApplication` → shown as made-for-COSMIC in COSMIC Store |
| Applet | [pop-os/cosmic-flatpak](https://github.com/pop-os/cosmic-flatpak) PR adding `app/<id>/<id>.json` (+ `cargo-sources.json`) | Flathub rejects desktop-specific components. Users add remote: `flatpak remote-add --if-not-exists --user cosmic https://apt.pop-os.org/cosmic/cosmic.flatpakrepo` |
| Either | Distro packages | Official repos ship `debian/`; use `just vendor` + `just build-vendored` for offline builds, `rootdir=` as DESTDIR |

Check TRADEMARK.md §5 naming before any submission (no `com.system76.` ID, `cosmic-ext-` prefix).

## Native install (justfile)

- `just` / `just build-release`, `just run`, `just check` (clippy pedantic), `just check-json`.
- `sudo just install` → `/usr` (ask the user first); user-local: `just prefix="$HOME/.local" install`;
  staged: `just rootdir=debian/tmp install`.
- Installs: binary, `target/xdgen/app.desktop` → `share/applications/<APP_ID>.desktop`,
  `target/xdgen/app.metainfo.xml` → `share/appdata/<APP_ID>.metainfo.xml`, icon → `share/icons/hicolor/scalable/apps/<APP_ID>.svg`.
- Template `uninstall` forgets the metainfo file; app template `build-*` uses `--locked` (needs committed `Cargo.lock`).

## Flatpak: app (Flathub)

Skeleton (`scripts/flatpak-manifest.sh` generates this):

```json
{
  "id": "io.github.user.MyApp",
  "runtime": "org.freedesktop.Platform",
  "runtime-version": "25.08",
  "base": "com.system76.Cosmic.BaseApp",
  "base-version": "stable",
  "sdk": "org.freedesktop.Sdk",
  "sdk-extensions": ["org.freedesktop.Sdk.Extension.rust-stable"],
  "command": "cosmic-ext-my-app",
  "finish-args": [
    "--share=ipc", "--socket=wayland", "--socket=fallback-x11", "--device=dri",
    "--talk-name=com.system76.CosmicSettingsDaemon",
    "--filesystem=xdg-config/cosmic:ro"
  ],
  "build-options": {
    "append-path": "/usr/lib/sdk/rust-stable/bin",
    "env": { "CARGO_HOME": "/run/build/cosmic-ext-my-app/cargo", "CARGO_NET_OFFLINE": "true" }
  },
  "modules": [{
    "name": "cosmic-ext-my-app",
    "buildsystem": "simple",
    "build-commands": [
      "cargo --offline fetch --manifest-path Cargo.toml --verbose",
      "cargo --offline build --release --verbose",
      "install -Dm0755 target/release/cosmic-ext-my-app -t ${FLATPAK_DEST}/bin/",
      "install -Dm0644 target/xdgen/app.desktop ${FLATPAK_DEST}/share/applications/${FLATPAK_ID}.desktop",
      "install -Dm0644 target/xdgen/app.metainfo.xml ${FLATPAK_DEST}/share/metainfo/${FLATPAK_ID}.metainfo.xml",
      "install -Dm0644 resources/icons/hicolor/scalable/apps/icon.svg ${FLATPAK_DEST}/share/icons/hicolor/scalable/apps/${FLATPAK_ID}.svg"
    ],
    "sources": [
      { "type": "git", "url": "https://github.com/user/cosmic-ext-my-app.git", "commit": "<sha>" },
      "cargo-sources.json"
    ]
  }]
}
```

- `com.system76.Cosmic.BaseApp` bundles `just`, Pop and COSMIC icon themes; its `runtime-version`
  must match yours — check <https://github.com/flathub/com.system76.Cosmic.BaseApp> before choosing
  (25.08 at time of writing; some apps already target 26.08).
- Flathub requires a pinned `commit` (or `tag`+`commit`), no network during build, and passes
  `flatpak-builder-lint`. Submission: fork `flathub/flathub`, branch from `new-pr`, add manifest +
  `cargo-sources.json`, open PR.

## Flatpak: applet (COSMIC Flatpak repo)

Same shape **without** `base`/`base-version`; observed baseline finish-args:

```
--share=ipc --socket=wayland [--socket=fallback-x11] [--device=dri]
--filesystem=xdg-config/cosmic:rw
--talk-name=com.system76.CosmicSettingsDaemon [--talk-name=com.system76.CosmicSettingsDaemon.*]
```

Install a symbolic icon (`<APP_ID>-symbolic.svg`) if the applet uses one. Test inside a clone of
`cosmic-flatpak`: `just build <id>` (runs flatpak-builder with `--sandbox --install-deps-from=flathub`).

## finish-args guidance

| Need | Arg | Notes |
|---|---|---|
| Display | `--socket=wayland`, `--socket=fallback-x11`, `--share=ipc` | Always |
| GPU (`wgpu`) | `--device=dri` | Omit if software-rendered |
| Live theme / `dbus-config` | `--talk-name=com.system76.CosmicSettingsDaemon` (+ `.*` for per-config proxies) | Always for COSMIC look |
| Read COSMIC theme | `--filesystem=xdg-config/cosmic:ro` | Flathub linter flags `:rw` (`finish-args-unnecessary-xdg-config-cosmic-rw-access`) |
| Persist own cosmic-config | add `--filesystem=xdg-config/cosmic/<APP_ID>:create` | Narrower than `xdg-config/cosmic:rw`; verify writes work in the sandbox |
| Network | `--share=network` | Only if used |
| Notifications | `--talk-name=org.freedesktop.Notifications` | or Notification portal (no permission) |
| Files | Prefer portals (file chooser) over `--filesystem=home/host` | Justify any static filesystem access |
| Audio | `--socket=pulseaudio` / `--filesystem=xdg-run/pipewire-0` | |

Every extra permission needs a one-line justification comment (YAML) or in the PR description.

## Generating cargo-sources.json

`flatpak-cargo-generator.py` from <https://github.com/flatpak/flatpak-builder-tools> (`cargo/`;
deps `aiohttp`, `tomlkit`, optional `PyYAML`; no console entry point):

```bash
python3 flatpak-cargo-generator.py Cargo.lock -o cargo-sources.json
# or without touching system Python:
uv run --no-project --with aiohttp --with tomlkit python flatpak-cargo-generator.py Cargo.lock -o cargo-sources.json
```

Regenerate after every `Cargo.lock` change. libcosmic and its git deps become `type: git` entries pinned
by commit. `scripts/flatpak-manifest.sh --cargo-sources` runs this if `FLATPAK_CARGO_GENERATOR` points
at the script.

## Build, lint, test locally

```bash
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.flatpak.Builder
flatpak run org.flatpak.Builder --user --install --force-clean --install-deps-from=flathub build-dir <APP_ID>.json
flatpak run <APP_ID>
flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest <APP_ID>.json
flatpak run --command=flatpak-builder-lint org.flatpak.Builder appstream target/xdgen/app.metainfo.xml
```

For a local (uncommitted) tree, temporarily replace the git source with `{ "type": "dir", "path": "." }`
— never submit that.
