---
name: dev-cosmic-app-create
description: "Create, extend, debug, and package native applications and panel applets for the System76 COSMIC desktop (COSMIC DE / cosmic-epoch) using Rust and libcosmic (iced). Use when asked to scaffold a COSMIC app or applet, write libcosmic code (Application trait, nav bar, menus, context drawer, dialogs, tasks, subscriptions, cosmic-config, theming, i18n), integrate with the COSMIC desktop (desktop entries, metainfo, D-Bus activation, portals, cosmic-settings-daemon), or package for Flathub / the COSMIC Flatpak repository."
---

# COSMIC app & applet development

Build COSMIC software from **current upstream sources**, not memory. libcosmic is a git dependency that
moves weekly; tutorials, the libcosmic book, and model training data lag behind it. Every API claim must be
checked against the libcosmic revision the project actually builds against.

## Ground rules

- **Source of truth order:** project `Cargo.lock` libcosmic rev → libcosmic source at that rev (`src/`,
  `examples/`) → official templates → official apps (`cosmic-edit`, `cosmic-files`, `cosmic-store`, …) →
  API docs → libcosmic book (conceptual only; several snippets are stale).
- Prefer libcosmic widgets (`cosmic::widget::*`) over raw iced widgets; never add a second GUI toolkit.
- Keep `update()` cheap: anything that blocks goes into a `Task` (one-shot) or `Subscription` (long-lived).
- Respect the [COSMIC trademark policy](https://github.com/pop-os/cosmic-epoch/blob/master/TRADEMARK.md) §5:
  third-party projects use the `cosmic-ext-` package prefix and **never** a `com.system76.` App ID;
  describe them as "for the COSMIC™ desktop".
- Apps and applets differ in runtime entrypoint, desktop-entry keys, metainfo `provides` ID, Flatpak
  sandbox, and distribution channel. Never assume one's packaging works for the other.

## Workflow

1. **Classify the work** and load only the matching references:

   ```sadkitti
   REFERENCE "references/upstream-sources.md"
   IF project is a standard application window
     REFERENCE "references/application.md"
     REFERENCE "references/tasks-subscriptions.md"
   IF project is a panel/dock applet
     REFERENCE "references/applet.md"
     REFERENCE "references/tasks-subscriptions.md"
   IF task touches config, theming, desktop entry, metainfo, icons, D-Bus, portals, notifications, i18n
     REFERENCE "references/desktop-integration.md"
   IF task touches justfile install, Flatpak, Flathub, cosmic-flatpak, distro packaging
     REFERENCE "references/packaging.md"
   IF task is a build failure, runtime bug, or verification step
     REFERENCE "references/testing-debugging.md"
   ```

2. **Check the environment** (read-only):
   `scripts/check-env.sh` — toolchain, system headers, packaging tools, COSMIC session. Report missing
   pieces with the printed install hints; do not install system packages without user approval.

3. **Discover the current API** before writing code:
    - `scripts/upstream.sh sync` — shallow-clone/refresh libcosmic, templates, and the book into the cache.
    - `scripts/upstream.sh rev <project>` — print the libcosmic commit pinned in `Cargo.lock`, the enabled
      libcosmic features, and the toolchain pin.
    - `scripts/upstream.sh pin <project>` — check out that exact libcosmic commit in the cache.
    - `scripts/upstream.sh grep '<regex>' [repo…]` — find real usages (e.g. `'fn context_drawer'`,
      `'file_chooser::open'`, `'watch_config'`). Add `--apps` to `sync` to include official apps.
    - When the API differs from a reference file here, trust upstream and say so in the report.

4. **Scaffold** (new projects only):
   `scripts/scaffold.sh -t app|applet -n cosmic-ext-<name> -i <rdnn.AppId> [-d …] [-l …] [-r …] [-o dir]`.
   Wraps `cargo generate` on the official template, enforces naming rules, fixes the app template's
   hard-coded `APP_ID`, and generates `Cargo.lock` (the template justfile builds with `--locked`).

5. **Implement incrementally.** Model → `Message` enum → `update` → `view`. Compile after each step (`cargo check`); copy patterns from the pinned
   libcosmic `examples/` or an official app with a similar
   feature rather than inventing APIs.

6. **Validate** before declaring done:
   `scripts/validate-project.sh <project>` — APP_ID consistency (code ↔ justfile ↔ desktop ↔ metainfo),
   app/applet desktop keys and `provides` ID, trademark naming, `desktop-file-validate`, `appstreamcli`,
   then `cargo fmt --check`, `cargo clippy`, `cargo test`. Use `--no-cargo` for metadata-only checks.

7. **Package** when asked:
   `scripts/flatpak-manifest.sh -p <project> [--git-url URL --commit SHA] [--cargo-sources]` emits an
   app (Flathub, `com.system76.Cosmic.BaseApp`) or applet (cosmic-flatpak) manifest skeleton. Review the
   `finish-args` against [packaging](references/packaging.md) — least privilege, justify every extra.

8. **Run it** when a COSMIC session is available: `just run` (apps). Applets must be installed and added
   to the panel — see [applet](references/applet.md#local-testing). Without a session, say runtime
   behaviour was not verified.

## Completion report

Always include:

- libcosmic commit + features built against, Rust toolchain used.
- What was implemented / changed (files).
- Results of `validate-project.sh` (or each cargo command) — paste failures verbatim.
- Runtime verification status (ran in COSMIC session / not verified and why).
- Any place where upstream contradicted this skill's references (so the skill can be updated).

## Scripts

| Script                        | Purpose                                                               | Side effects                                                           |
|-------------------------------|-----------------------------------------------------------------------|------------------------------------------------------------------------|
| `scripts/check-env.sh`        | Verify toolchain, headers, packaging tools, session                   | none                                                                   |
| `scripts/upstream.sh`         | Cache/inspect upstream repos, resolve pinned libcosmic rev, grep APIs | writes only to `$COSMIC_SRC_CACHE` (default `~/.cache/cosmic-dev-src`) |
| `scripts/scaffold.sh`         | New app/applet from official template                                 | creates `<out>/<name>/`, network (git, crates.io)                      |
| `scripts/validate-project.sh` | Metadata + cargo quality gates                                        | builds in `target/`                                                    |
| `scripts/flatpak-manifest.sh` | Manifest skeleton (+ `cargo-sources.json`)                            | writes manifest into project; refuses to overwrite without `-f`        |

All scripts support `-h`, use strict mode, and accept `DEBUG=1`.
