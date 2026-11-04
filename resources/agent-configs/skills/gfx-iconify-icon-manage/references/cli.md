# iconify-cli reference

Sources: https://github.com/bytelab-studio/iconify-cli, https://iconify-cli.bytelab.studio/getting-started.html

## Commands

| Command | Purpose |
|---|---|
| `iconify config init` | Create `.iconify` in the current directory |
| `iconify search <query> [-p <prefix>]` | List matching `prefix:name` IDs |
| `iconify download <id> [<id>...]` | Write icon files using the configured template |

Flags override `.iconify` values.

| Command | Flags |
|---|---|
| `search` | `-l/--limit`, `-o/--offset`, `-p/--prefix` |
| `download` | `-t/--template`, `-p/--placement`, `-n/--naming`, `-o/--output` (base folder) |
| both | `--config-host`, `--config-port`, `--no-proxy`, `-h` |

Note `-p` means prefix for `search` but placement for `download`.

## Naming examples (`mdi:person-outline`)

| `naming` | File stem |
|---|---|
| `lower` | `personoutline` |
| `upper` | `PERSONOUTLINE` |
| `camel` | `personOutline` |
| `pascal` | `PersonOutline` |
| `kebab` | `person-outline` |

## Placement example (`grouped`, `pascal`, `raw`)

```
icons/
├── mdi/
│   ├── Home.js
│   └── Person.js
└── mdi-light/
    └── Person.js
```

## Generated header

Each file starts with a comment holding icon ID, collection, license, version, author and download time.

## Templates

`svg` (file with license comment), `raw` / `raw-ts` (ESM default export of the SVG string), `vue` (SFC with `<template>`), `php` (function `{collection}_{icon}()` returning the SVG), `jsx`, `tsx` (default-exported component).
