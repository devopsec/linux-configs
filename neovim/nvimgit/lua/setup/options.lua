-- Enable 24bit True Color
vim.opt.termguicolors = true

-- Backspace modification
vim.opt.backspace = { "indent", "eol", "start" }

-- Nerd Font support toggle for plugin/UI icons
vim.g.have_nerd_font = true

-- Statusline, ruler, cmd, filename
vim.opt.showmode = false
vim.opt.ruler = false
vim.opt.showcmd = false
vim.opt.shortmess:append("F")
-- noice.nvim owns command-line interaction in a centered popup.
vim.opt.cmdheight = 0

-- Disable audio bell on error
vim.opt.errorbells = false

-- Share the system clipboard w/ neovim
vim.opt.clipboard:append("unnamedplus")

-- Show matching brackets
vim.opt.showmatch = true

-- Do smart case matching on searches
vim.opt.smartcase = true

-- Default tab settings
vim.opt.tabstop = 4         -- A hard tab is 4 spaces wide
vim.opt.shiftwidth = 4      -- Indentation commands use 4 spaces
vim.opt.softtabstop = 4     -- Backspace and Tab keys treat 4 spaces as a single unit
vim.opt.expandtab = true    -- Insert spaces when the Tab key is pressed

-- UI mouse support (wheel scrolling is kept mode-local in keymaps)
vim.opt.mouse = "nih"
vim.opt.mousemodel = "popup_setpos"

-- Per-mode cursor shapes (block in normal/visual/select, vertical bar in
-- insert/cmdline/visual-exclusive, horizontal bar in replace/cmdline-replace/
-- operator-pending). Pinned explicitly (it matches Neovim's own built-in
-- default) so classic vim's guicursor in vimrc.vim can be kept in sync.
vim.opt.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,sm:block-blinkwait175-blinkoff150-blinkon175"

-- Line numbers / Gutter settings
local function apply_gutter_options()
  vim.opt.number = true             -- enable line numbers in gutter
  vim.opt.relativenumber = false    -- fixed position line numbers (do not scroll)
  vim.opt.numberwidth = 3
  vim.opt.signcolumn = "auto"
  vim.opt.foldcolumn = "0"
  -- Keep the native number/sign columns as the only gutter decoration so every
  -- split uses the same width and alignment.
  vim.opt.statuscolumn = ""
end

-- Default split created below / right
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Improved fill characters
vim.opt.fillchars:append({
  horiz     = '━', -- Heavy horizontal line
  horizup   = '┻',
  horizdown = '┳',
  vert      = '┃', -- Heavy vertical line
  vertleft  = '┨',
  vertright = '┣',
  verthoriz = '╋',
  eob = "░",       -- Faint stipple pattern (Unicode U+2591)
  fold = "─",      -- Horizontal line connecting the fold
  foldopen = "",
  foldclose = "",
  foldsep = " ", -- hides repeated fold levels
  msgsep    = '‾', -- Overline for message separator
  diff      = '░' -- Dotted pattern for diff blocks
})

-- Colors for the fillchars and native gutter. The gutter is themed with a
-- separated panel shade (NormalFloat's bg, e.g. catppuccin's mantle) kept
-- distinct from Normal, so re-apply it after every colorscheme change.
local function apply_gutter_highlights()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local normal_float = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false })
  local panel_bg = normal_float.bg or normal.bg
  if not panel_bg then
    return
  end

  for _, group in ipairs({
    "SignColumn",
    "FoldColumn",
    "LineNr",
    "LineNrAbove",
    "LineNrBelow",
    "CursorLineNr",
    "CursorLineSign",
    "GitSignsAdd",
    "GitSignsChange",
    "GitSignsDelete",
  }) do
    local highlight = vim.api.nvim_get_hl(0, { name = group, link = false })
    highlight.bg = panel_bg
    vim.api.nvim_set_hl(0, group, highlight)
  end

  vim.api.nvim_set_hl(0, "EndOfBuffer", { fg = "#999999", bg = panel_bg })
  vim.api.nvim_set_hl(0, "VertSplit", { fg = "#999999", bg = panel_bg })
  vim.api.nvim_set_hl(0, "FoldColumn", { fg = "#999999", bg = panel_bg })
end

apply_gutter_options()
apply_gutter_highlights()

local gutter_group = vim.api.nvim_create_augroup("NvimgitGutterStyle", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = gutter_group,
  callback = apply_gutter_highlights,
})

-- Keep the native statusline visible for each split; nvimgit has no
-- global statusline plugin to consolidate it.
vim.opt.laststatus = 2

-- Re-apply after lazy.nvim startup options have settled.
vim.defer_fn(function()
  apply_gutter_options()
  apply_gutter_highlights()
  vim.opt.cmdheight = 0
  vim.opt.laststatus = 2
end, 0)
vim.api.nvim_create_autocmd("User", {
  group = gutter_group,
  pattern = "VeryLazy",
  callback = function()
    apply_gutter_options()
    apply_gutter_highlights()
    vim.opt.cmdheight = 0
    vim.opt.laststatus = 2
  end,
})

-- Max characters in a line highlighted
vim.opt.synmaxcol = 1000

-- Redrawtime
vim.opt.redrawtime = 5000

-- Timeout for keys
vim.opt.timeout = true
vim.opt.timeoutlen = 300
vim.opt.ttimeoutlen = 10
