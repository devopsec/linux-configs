# Emacs

## Frameworks

- **vanilla** `init.el` / `early-init.el`
- **Doom Emacs** — `doom/config.el`, `doom/packages.el`; use `doom sync` when packages change
- **Spacemacs** — layers in `.spacemacs`

## Rules

- Match the framework’s package declaration style (`use-package`, `package!`, layers).
- Prefer `use-package` `:bind` / `:custom` already in file.
- Batch check: `emacs --batch -l init.el` (may need `--quick` variants).

## UI

- Mode line packages (doom-modeline, telephone-line): one only.
- Do not mix evil and non-evil key conventions unless the config already does.
