local keyopts = { silent = true }

-- <ESC> (terminal mode) to return to normal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", keyopts)

-- <F1> to clear search highlighting
vim.keymap.set("n", "<F1>", ":nohlsearch<CR>", keyopts)

-- <F2> toggle ANSI escape rendering for current buffer
vim.keymap.set("n", "<F2>", ":AnsiToggle<CR>", keyopts)

-- <F3> to replace tabs/spaces w/ correct type (depends on utility functions)
vim.keymap.set("n", "<F3>", ":RetabIndent<CR>", keyopts)

-- <Shift>+I to change to insert paste mode
vim.keymap.set("n", "<S-I>", ":set invpaste<CR>", keyopts)

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

-- coq_nvim completion menu navigation (mirrors the old blink.cmp completion_keymap table)
-- falls back to the key's normal behavior when the popup menu isn't visible
local function pum(key)
  return vim.fn.pumvisible() == 1 and key or nil
end

local completion_keyopts = { expr = true, silent = true }

-- <Tab>|<End> to accept the selected completion item
vim.keymap.set("i", "<Tab>", function()
  return pum("<C-y>") or "<Tab>"
end, completion_keyopts)
vim.keymap.set("i", "<End>", function()
  return pum("<C-y>") or "<End>"
end, completion_keyopts)

-- <Esc>|<Home> to cancel/close the completion menu
vim.keymap.set("i", "<Esc>", function()
  return pum("<C-e>") or "<Esc>"
end, completion_keyopts)
vim.keymap.set("i", "<Home>", function()
  return pum("<C-e>") or "<Home>"
end, completion_keyopts)

-- <Up>|<Down> to select the previous/next completion item
vim.keymap.set("i", "<Up>", function()
  return pum("<C-p>") or "<Up>"
end, completion_keyopts)
vim.keymap.set("i", "<Down>", function()
  return pum("<C-n>") or "<Down>"
end, completion_keyopts)

-- <PageUp>|<PageDown> to jump 10 completion items at a time
vim.keymap.set("i", "<PageUp>", function()
  return pum(string.rep("<C-p>", 10)) or "<PageUp>"
end, completion_keyopts)
vim.keymap.set("i", "<PageDown>", function()
  return pum(string.rep("<C-n>", 10)) or "<PageDown>"
end, completion_keyopts)

-- <C-F2> to toggle coq_nvim's (non 3rd-party) snippet completion source
-- on/off; it starts disabled by default (see lua/plugins/syntax.lua)
vim.keymap.set({ "n", "i" }, "<C-F2>", function()
  local ok, toggle = pcall(require, "coq.lib.producers.toggle")
  if not ok then
    return
  end
  local currently_enabled = toggle.is_enabled("snippets")
  vim.cmd("COQ source " .. (currently_enabled and "off" or "on") .. " snippets")
end, keyopts)
