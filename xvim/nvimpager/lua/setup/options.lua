-- Settings for nvimpager
-- https://github.com/lucc/nvimpager/blob/main/nvimpager.md#configuration
nvimpager.follow            = false
nvimpager.follow_interval   = 500
nvimpager.git_colors        = false
nvimpager.maps              = false


-- General configurations
local opt = vim.opt

-- Backspace modification
opt.backspace = { "indent", "eol", "start" }

-- Statusline, ruler, cmd, filename
opt.showmode = false
opt.ruler = false
opt.showcmd = false
opt.shortmess:append("F")
opt.cmdheight = 1

-- Disable audio bell on error
opt.errorbells = false

-- Share the system clipboard w/ neovim
opt.clipboard:append("unnamedplus")

-- Show matching brackets
opt.showmatch = true

-- Do smart case matching on searches
opt.smartcase = true

-- Default tab settings
vim.opt.tabstop = 4         -- A hard tab is 4 spaces wide
vim.opt.shiftwidth = 4      -- Indentation commands use 4 spaces
vim.opt.softtabstop = 4     -- Backspace and Tab keys treat 4 spaces as a single unit
vim.opt.expandtab = true    -- Insert spaces when the Tab key is pressed

-- Mouse support (user has it disabled)
opt.mouse = ""

-- Default split created below / right
opt.splitbelow = true
opt.splitright = true

-- Space between vertical splits
opt.fillchars:append({ vert = " " })

-- Enable 24bit True Color
opt.termguicolors = true

-- Always show the status bar
opt.laststatus = 3

-- Max characters in a line highlighted
opt.synmaxcol = 1000

-- Redrawtime
opt.redrawtime = 5000

-- Timeout for keys
opt.timeout = true
opt.timeoutlen = 1000
opt.ttimeoutlen = 0
