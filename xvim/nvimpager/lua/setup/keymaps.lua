local keyopts = { silent = true }

-- <ESC> (terminal mode) to return to normal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", keyopts)

-- <F1> to clear search highlighting
vim.keymap.set("n", "<F1>", ":nohlsearch<CR>", keyopts)

-- <Shift>+I to toggle insert paste mode (normal mode)
vim.keymap.set("n", "<S-I>", ":set invpaste<CR>", keyopts)

-- <F3> to replace tabs/spaces w/ correct type (depends on utility functions)
vim.keymap.set("n", "<F3>", ":RetabIndent<CR>", keyopts)

-- <shift>+<tab> to un-indent
vim.keymap.set("n", "<S-Tab>", "<<", keyopts)
vim.keymap.set("i", "<S-Tab>", "<C-D>", keyopts)

-- <ctrl>+<arrow key> to navigate window splits
vim.keymap.set("n", "<C-Left>", "<C-W>h", keyopts)
vim.keymap.set("n", "<C-Right>", "<C-W>l", keyopts)
vim.keymap.set("n", "<C-Up>", "<C-W>k", keyopts)
vim.keymap.set("n", "<C-Down>", "<C-W>j", keyopts)

-- <ctrl>+<page up>|<page down> to navigate tabs
vim.keymap.set("n", "<C-PageDown>", ":tabnext<CR>", keyopts)
vim.keymap.set("n", "<C-PageUp>", ":tabprevious<CR>", keyopts)

-- <ctrl>+<t>|<w> to create or close a tab
vim.keymap.set("n", "<C-t>", ":$tabnew<CR>", keyopts)
vim.keymap.set("n", "<C-w>", ":tabclose<CR>", keyopts)

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
