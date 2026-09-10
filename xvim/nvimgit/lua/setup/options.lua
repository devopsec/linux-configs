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
vim.opt.cmdheight = 1

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

-- UI Mouse Support in normal / insert / help modes
vim.opt.mouse = "nih"
vim.opt.mousemodel = "popup_setpos"

-- Line numbers / Gutter settings
vim.opt.number = true             -- enable line numbers in gutter
vim.opt.relativenumber = false    -- fixed position line numbers (do not scroll)

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

-- Always show the status bar
vim.opt.laststatus = 2

-- Max characters in a line highlighted
vim.opt.synmaxcol = 1000

-- Redrawtime
vim.opt.redrawtime = 5000

-- Timeout for keys
vim.opt.timeout = true
vim.opt.timeoutlen = 300
vim.opt.ttimeoutlen = 0
