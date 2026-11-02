-- disable netrw (nvim-tree replaces it)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

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

-- Command-line Tab completion: the first <Tab> fills the longest common
-- prefix and opens the popup menu without a selection; navigation inside the
-- menu is handled by lua/setup/menus.lua (<Up>/<Down>, <Home>/<End>, ...).
-- 'wildcharm' lets those mappings trigger completion with a non-typed key.
vim.opt.wildmenu = true
vim.opt.wildmode = "longest:full,full"
vim.opt.wildoptions = "pum"
vim.opt.wildcharm = 26 -- <C-Z>

-- Opaque popup menus and floating windows (no translucency)
vim.opt.pumblend = 0
vim.opt.winblend = 0
vim.opt.guifont = "JetBrainsMono Nerd Font:h11,JetBrains Mono:h11"

-- Disable audio bell on error
vim.opt.errorbells = false

-- Share the system clipboard w/ neovim
vim.opt.clipboard = "unnamedplus"

-- Show matching brackets
vim.opt.showmatch = true

-- Do smart case matching on searches
vim.opt.smartcase = true

-- Default tab settings
vim.opt.tabstop = 4         -- A hard tab is 4 spaces wide
vim.opt.shiftwidth = 4      -- Indentation commands use 4 spaces
vim.opt.softtabstop = 4     -- Backspace and Tab keys treat 4 spaces as a single unit
vim.opt.expandtab = true    -- Insert spaces when the Tab key is pressed

-- Enable list mode so indent-blankline.nvim can safely draw its virtual
-- text arrows over empty, native tab characters instead of fighting them
vim.opt.list = true
vim.opt.listchars = {
  tab = "  ",   -- kept empty so indent-blankline can draw arrows over it
  trail = "·",
  nbsp = "␣",
}

-- UI mouse support in every mode: the terminal only reports wheel events
-- while the mouse is enabled for the current mode, otherwise it sends
-- <Up>/<Down> keys instead (which move the cursor or browse history and
-- can change the mode). Native wheel scrolling keeps the current mode.
vim.opt.mouse = "a"
vim.opt.mousehide = true
vim.opt.mousemodel = "popup_setpos"
vim.opt.mousemoveevent = false
vim.opt.mousescroll = "ver:5,hor:10"

-- Per-mode cursor shapes (block in normal/visual/select, vertical bar in
-- insert/cmdline/visual-exclusive, horizontal bar in replace/cmdline-replace/
-- operator-pending). Pinned explicitly (it matches Neovim's own built-in
-- default) so classic vim's guicursor in vimrc.vim can be kept in sync.
vim.opt.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,sm:block-blinkwait175-blinkoff150-blinkon175"

-- Line numbers / Gutter settings
vim.opt.number = true             -- enable line numbers in gutter
vim.opt.relativenumber = false    -- fixed position line numbers (do not scroll)
vim.opt.numberwidth = 3
vim.opt.signcolumn = "auto"
vim.opt.foldcolumn = "0"
-- Let the native number/sign columns own the gutter; this avoids LazyVim's
-- statuscolumn adding a second, split-dependent decoration column.
vim.opt.statuscolumn = ""

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

-- Colors for the fillchars
vim.api.nvim_set_hl(0, "EndOfBuffer", { fg = "#999999" })
vim.api.nvim_set_hl(0, "VertSplit", { fg = "#999999" })
vim.api.nvim_set_hl(0, "FoldColumn", { fg = "#999999" })

-- Keep one global statusline at the bottom after reclaiming cmdheight.
vim.opt.laststatus = 3

-- Re-apply after lazy.nvim/LazyVim startup options have settled.
vim.defer_fn(function()
  vim.opt.cmdheight = 0
  vim.opt.laststatus = 3
  vim.opt.pumblend = 0
end, 0)
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    vim.opt.cmdheight = 0
    vim.opt.laststatus = 3
    vim.opt.pumblend = 0
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
