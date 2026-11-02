# Vim and vimpager

## Files

- `~/.vimrc` or `~/.vim/vimrc`
- after/plugin, ftplugin under `~/.vim/`
- vimpager: `~/.vimpagerrc` — keep startup light

## Plugin managers

- **vim-plug:** `call plug#begin()` … `plug#end()`; `Plug 'org/repo'`
- **Vundle:** legacy; migrate carefully if asked
- **pack/** native packages under `~/.vim/pack/`

## Statusline / UI

- Prefer existing plugin (lightline, airline, wilder) over inventing a second statusline.
- Mouse: `set mouse=a` vs modes — document tradeoffs for SSH.
- Popup/completion: check conflicts between coc, mucomplete, coq, etc.

## Safe edit pattern

1. Locate option or map with search.
2. Patch in place; keep user comments.
3. `vim -Nu NONE -S <script>` only for isolated repro; normal check sources real rc.
