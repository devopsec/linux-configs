# Micro and Zed (JSON configs)

## Micro

- `$XDG_CONFIG_HOME/micro/settings.json` — editor options (default XDG home under the user profile)
- `bindings.json` — key maps
- `init.lua` optional for plugins
- Validate JSON after edits; trailing commas invalid

## Zed

- User: `$XDG_CONFIG_HOME/zed/settings.json`, `keymap.json`
- Project: `.zed/settings.json` (team-shared)
- Prefer project settings only when the user wants repo-level defaults
- Themes/fonts: keep portable; note OS-specific font names

## Shared JSON rules

- Parse-check before finish.
- Preserve key order when the file is human-curated if easy; otherwise stable sort is fine if already sorted.
- Comments: standard JSON forbids comments — do not introduce `//` unless the tool explicitly allows JSONC (Zed often allows JSONC — match existing file).
