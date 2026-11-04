---
name: gfx-iconify-icon-manage
description: "Find and add icons to a project as real files using Iconify and iconify-cli. Use when asked to add, search, download, or replace icons or SVGs (Material Design, Lucide, Tabler, Phosphor, etc.), or when a project needs icon assets, icon components (svg/js/ts/vue/php/jsx/tsx), or a .iconify config. Searches 200+ Iconify collections via `iconify search` and writes icon files into the repo via `iconify download` (file-native, no runtime API calls, no MCP, no inline pasting)."
---

# Iconify Icon Manage

Icons are committed as files in the project. Find them with `iconify search`, write them with `iconify download`, and reference them from code. Never
hotlink the Iconify API at runtime and never hand-paste SVG markup from memory.

## Setup

Run without installing, or install once:

```bash
npx iconify-cli@latest <command>
npm install -g iconify-cli # then: iconify <command>
```

Standalone binaries (v1.1.2+) exist on the GitHub releases page of `bytelab-studio/iconify-cli`.

## Workflow

1. **Detect the convention.** Look for an existing `.iconify` file and existing icon directory (`assets/icons`, `src/icons`, `public/icons`, ...).
   Reuse them. Match the project's framework and collection (do not mix collections in one UI without asking).
2. **Initialize config once** (only if no `.iconify` exists): `iconify config init`, then set `[output]` keys (below). Commit `.iconify`.
3. **Search**: `iconify search <query> [-p <prefix>]`, e.g. `iconify search home -p mdi`. Output is a list of `prefix:name` IDs. Prefer one collection
   per project; pick by name and style (outline vs solid).
4. **Download**: `iconify download mdi:home mdi:person-outline`. Several IDs and collections per call are fine.
5. **Reference** the generated files from code using the project's own import style.
6. **Verify**: files exist at the configured path, each header has a license, and the app or build still passes.

## Config (`.iconify`, INI)

```ini
[output]
out_dir = assets/icons
placement = grouped
naming = kebab
template = svg
```

| Key                   | Values                                                                        |
|-----------------------|-------------------------------------------------------------------------------|
| `out_dir`             | Path relative to the config file (default: cwd)                               |
| `placement`           | `flat`, `prefixed` (prefix in filename), `grouped` (subfolder per collection) |
| `naming`              | `lower`, `upper`, `camel`, `pascal`, `kebab`                                  |
| `template`            | `svg`, `raw` (ESM JS), `raw-ts`, `vue`, `php`, `jsx`, `tsx`                   |
| `[api]` `host`/`port` | Default `api.iconify.design` / `443`                                          |

Precedence: CLI flags > `.iconify` > defaults. Choose `template` by consumer: plain files or CSS/HTML or desktop apps use `svg`; web frameworks use
the matching component template. Default recommendation: `svg`, `grouped`, `kebab`.

## Rules

- Downloaded SVGs use `currentColor` and `1em` sizing, so style them via CSS `color`/`font-size` and do not edit the path data.
- The CLI does not check for existing files and overwrites them. Check `git status` first when re-downloading.
- Keep the generated license header; icon licenses differ per collection (check it when adding a new collection, and note non-permissive ones for the
  user).
- Only download icons actually used. List IDs in the commit/PR description or a short note near the icon directory when the project tracks them.
- Search output is large: pipe through `head` or restrict with `-p`.
- Command details and file-name examples: [references/cli.md](references/cli.md).
