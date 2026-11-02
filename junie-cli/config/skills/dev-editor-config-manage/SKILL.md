---
name: "dev-editor-config-manage"
description: "Create, update, or fix text-editor and pager configurations for vim, vimpager, neovim, nvimpager, emacs, micro, and Zed — including statuslines, keymaps, plugins, colorschemes, and dotfile layouts. Use when asked to change vim/nvim/emacs/micro/zed config, fix status bar/UI, migrate plugin managers, or tune vimpager/nvimpager."
---

# Editor config manage

Safely edit editor/pager dotfiles with backup-friendly, reversible changes.

## Supported targets

| Editor / pager | Common paths | Notes |
|----------------|--------------|-------|
| **vim** | `~/.vimrc`, `~/.vim/`, `$XDG_CONFIG_HOME/vim/` | vim-plug, Vundle, native packages |
| **vimpager** | `~/.vimpagerrc`, env `VIMPAGER_RC` | Often shares vim runtime |
| **neovim** | `$XDG_CONFIG_HOME/nvim/init.lua` or `init.vim`, `lua/**` | lazy.nvim, packer, vim-plug |
| **nvimpager** | `nvimpager` config / wrapper scripts | Pager-only subset of nvim |
| **emacs** | `~/.emacs.d/init.el`, `early-init.el`, doom/spacemacs | Lisp; respect framework |
| **micro** | `$XDG_CONFIG_HOME/micro/settings.json`, `bindings.json` | JSON configs |
| **zed** | `$XDG_CONFIG_HOME/zed/settings.json`, `keymap.json` | JSON; project `.zed/` |

Load only the matching reference:

```sadkitti
IF target is vim or vimpager
  REFERENCE "references/vim-family.md"
IF target is neovim or nvimpager
  REFERENCE "references/neovim-family.md"
IF target is emacs
  REFERENCE "references/emacs.md"
IF target is micro or zed
  REFERENCE "references/json-editors.md"
```

## Workflow

1. **Detect target**
   - User-named editor wins. Else infer from path (`nvim`, `.vimrc`, `zed/settings.json`).
   - Detect plugin manager and whether config is Lua vs Vimscript vs Lisp vs JSON.

2. **Snapshot**
   - Before edits, note current relevant sections (statusline, maps, plugins).
   - Prefer small diffs; do not reformat entire dotfiles.

3. **Change**
   - Match existing style (tabs, option syntax, comment density).
   - UI fixes (statusline, popup, mouse): change one subsystem at a time.
   - Plugin migrations: install/remove steps must be explicit and reversible.

4. **Verify**
   - Headless checks when available:
     - `vim -e -c 'source $MYVIMRC' -c qa`
     - `nvim --headless -c 'qa'`
     - `emacs --batch -l ~/.emacs.d/init.el`
     - JSON: parse with `python -m json.tool`
   - Report what cannot be verified headlessly (GUI font, truecolor).

5. **Document**
   - If the config lives in a dotfiles repo with README, update the relevant blurb.
   - Call out new plugin dependencies and install commands.

## Rules

- **Backup before edit** — copy the target file to `/tmp/editor-config-backup-<name>` when changing non-trivial options.
- Touch only the editor the user named; do not "while we're here" rewrite sibling tools.
- Prefer `$XDG_CONFIG_HOME` / project-local configs over hard-coded `/home/...` paths in skill text and patches.
- Keep changes reversible and explain the option in one line.

- Never overwrite user plugin lock state without saying so.
- Never commit credential material from editor local history.
- GUI-only settings: keep optional and documented.
- Pagers (`vimpager`/`nvimpager`): avoid heavy plugins that break stdin paging.

## References

- [references/vim-family.md](references/vim-family.md)
- [references/neovim-family.md](references/neovim-family.md)
- [references/emacs.md](references/emacs.md)
- [references/json-editors.md](references/json-editors.md)
