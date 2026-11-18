local keyopts = { silent = true }

-- Mouse wheel scrolling is native ('mouse' covers every mode, see
-- lua/setup/options.lua); popup menu wheel handling lives in lua/setup/menus.lua.

-- <ESC> (terminal mode) to return to normal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", keyopts)

-- <F1> to clear search highlighting
vim.keymap.set("n", "<F1>", ":nohlsearch<CR>", keyopts)

-- <Shift>+I to toggle insert paste mode (normal mode)
vim.keymap.set("n", "<S-I>", ":set invpaste<CR>", keyopts)

-- <F3> to replace tabs/spaces w/ correct type (depends on utility functions)
vim.keymap.set("n", "<F3>", ":RetabIndent<CR>", keyopts)

-- <shift>+<tab> to un-indent (the insert-mode variant is popup-menu aware,
-- see lua/setup/menus.lua)
vim.keymap.set("n", "<S-Tab>", "<<", keyopts)

-- <ctrl>+<arrow key> to navigate window splits
vim.keymap.set("n", "<C-Left>", "<C-W>h", keyopts)
vim.keymap.set("n", "<C-Right>", "<C-W>l", keyopts)
vim.keymap.set("n", "<C-Up>", "<C-W>k", keyopts)
vim.keymap.set("n", "<C-Down>", "<C-W>j", keyopts)

-- <ctrl>+<page up>|<page down> to navigate tabs (wraps around)
vim.keymap.set("n", "<C-PageDown>", ":tabnext<CR>", keyopts)
vim.keymap.set("n", "<C-PageUp>", ":tabprevious<CR>", keyopts)

-- <ctrl>+<home>|<end> to jump to the first/last tab
vim.keymap.set("n", "<C-Home>", ":tabfirst<CR>", keyopts)
vim.keymap.set("n", "<C-End>", ":tablast<CR>", keyopts)

-- <ctrl>+<alt>+<page up>|<page down> to navigate window splits (wraps around)
vim.keymap.set("n", "<C-A-PageDown>", "<C-W>w", keyopts)
vim.keymap.set("n", "<C-A-PageUp>", "<C-W>W", keyopts)

-- <ctrl>+<alt>+<home>|<end> to jump to the first/last window split
vim.keymap.set("n", "<C-A-Home>", "<C-W>t", keyopts)
vim.keymap.set("n", "<C-A-End>", "<C-W>b", keyopts)

-- <ctrl>+<alt>+<arrow key> to navigate to the closest window split in that
-- direction (no wrapping)
vim.keymap.set("n", "<C-A-Left>", "<C-W>h", keyopts)
vim.keymap.set("n", "<C-A-Right>", "<C-W>l", keyopts)
vim.keymap.set("n", "<C-A-Up>", "<C-W>k", keyopts)
vim.keymap.set("n", "<C-A-Down>", "<C-W>j", keyopts)

-- NOTE: no <C-t>/<C-w> tab bindings here (unlike nvim and nvimgit).
-- nvimpager is a single-shot pager with no real multi-tab workflow, and <C-t>
-- must stay free for Neovim's built-in tag-stack pop ("back") so following a
-- manpage cross-reference via <C-]> (man.lua's tagfunc) can be reversed.

-- x|X to cut text (not using the default register)
vim.keymap.set("n", "x", '""d', keyopts)
vim.keymap.set("n", "X", '""D', keyopts)
vim.keymap.set("v", "x", '""d', keyopts)
vim.keymap.set("v", "X", '""D', keyopts)

-- d|D to delete text (using the black hole register)
vim.keymap.set("n", "d", '"_d', keyopts)
vim.keymap.set("n", "D", '"_D', keyopts)
vim.keymap.set("v", "d", '"_d', keyopts)
vim.keymap.set("v", "D", '"_D', keyopts)

-- Split resizing (handled by functions)
-- These will be set by autocommands calling the utility function.

-- <Space> (leader) mappings, listed by the which-key menu (hydra mode, see
-- lua/setup/whichkey.lua); vimpager's vimpagerrc defines the same set.
-- Prompts (:help, :Man, :Info) are not <silent>, so the command line shows.
local function leader(lhs, rhs, desc, silent)
  vim.keymap.set("n", "<leader>" .. lhs, rhs, { silent = silent ~= false, desc = desc })
end

leader("qq", "<Cmd>qa<CR>", "Quit All")
leader("-", "<C-W>s", "Split Window Below")
leader("|", "<C-W>v", "Split Window Right")
leader("?", function()
  require("which-key").show({ global = false })
end, "Buffer Keymaps (which-key)")

leader("bb", "<C-^>", "Switch to Other Buffer")
leader("bn", "<Cmd>bnext<CR>", "Next Buffer")
leader("bp", "<Cmd>bprevious<CR>", "Previous Buffer")
leader("bd", "<Cmd>bdelete<CR>", "Delete Buffer")

leader("sw", "*", "Search Word Under Cursor")
leader("sh", ":help ", "Help Page", false)
leader("sm", ":Man ", "Man Page", false)
leader("si", ":Info ", "Info Manual", false)

leader("uw", "<Cmd>setlocal wrap! wrap?<CR>", "Toggle Wrap")
leader("ul", "<Cmd>setlocal number! number?<CR>", "Toggle Line Numbers")
leader("uL", "<Cmd>setlocal relativenumber! relativenumber?<CR>", "Toggle Relative Number")
leader("uc", "<Cmd>setlocal cursorline! cursorline?<CR>", "Toggle Cursor Line")
leader("uh", "<Cmd>set hlsearch! hlsearch?<CR>", "Toggle Search Highlight")
leader("ur", "<Cmd>nohlsearch<Bar>redraw!<CR>", "Redraw / Clear hlsearch")

leader("wd", "<C-W>c", "Delete Window")
leader("wo", "<C-W>o", "Close Other Windows")
leader("ww", "<C-W>p", "Other Window")
