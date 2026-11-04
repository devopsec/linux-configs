# Neovim and nvimpager

## Layout

- Lua-first: `init.lua`, `lua/config/*.lua`, `lua/plugins/*.lua`
- Vimscript still valid via `init.vim`

## Plugin managers

- **lazy.nvim** — specs in `lua/plugins`; prefer structured plugin files
- **packer** — legacy
- **vim-plug** — still seen in hybrid configs

## UI tasks common in sessions

- Statusline (lualine, heirline): sections, separators, slow components
- Cursor/mouse scroll, cmdline popup geometry
- Treesitter / LSP: enable per filetype; do not blanket-disable errors silently

## nvimpager

- Config should not assume TTY width forever; test with pipes when possible.
- Disable competing statuslines that spam the pager footer.

## Check

```bash
nvim --headless "+checkhealth" "+qa" 2>/tmp/nvim-health.txt || true
nvim --headless -c 'lua vim.notify("ok")' -c qa
```
