-- ============================================================================
-- Settings for nvimpager
-- https://github.com/lucc/nvimpager/blob/main/nvimpager.md#configuration
-- ============================================================================
nvimpager.follow            = false
nvimpager.follow_interval   = 500
nvimpager.git_colors        = false
nvimpager.maps              = false

-- ============================================================================
-- General nvim settings
-- ============================================================================

-- Backspace modification
vim.opt.backspace = { "indent", "eol", "start" }

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
vim.g.have_nerd_font = true

-- Per-mode cursor shapes (block in normal/visual/select, vertical bar in
-- insert/cmdline/visual-exclusive, horizontal bar in replace/cmdline-replace/
-- operator-pending). Pinned explicitly (it matches Neovim's own built-in
-- default) so classic vim's guicursor in vimrc.vim can be kept in sync.
vim.opt.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,sm:block-blinkwait175-blinkoff150-blinkon175"

-- Line numbers / Gutter settings
local function apply_gutter_options()
  vim.opt.number = false
  vim.opt.relativenumber = false
  vim.opt.numberwidth = 3
  vim.opt.signcolumn = "auto"
  vim.opt.foldcolumn = "0"
  vim.opt.statuscolumn = ""
end

-- Default split created below / right
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Match nvimgit's compact, heavy split separators.
vim.opt.fillchars:append({
  horiz     = "━",
  horizup   = "┻",
  horizdown = "┳",
  vert      = "┃",
  vertleft  = "┨",
  vertright = "┣",
  verthoriz = "╋",
  eob       = "░",
  fold      = "─",
  foldopen  = "",
  foldclose = "",
  foldsep   = " ",
  msgsep    = "‾",
  diff      = "░",
})

-- Enable 24bit True Color
vim.opt.termguicolors = true

-- Keep a statusline for each pager split; there is no global statusline plugin.
-- Man pages drop it (and the end-of-buffer filler) so the footer is the last line.
local function apply_pager_view()
  local is_man = vim.api.nvim_buf_get_name(0):match("^man://") ~= nil
  vim.opt.laststatus = is_man and 0 or 2
  vim.opt.fillchars:append({ eob = is_man and " " or "░" })
end

apply_pager_view()

-- The gutter is themed with a separated panel shade (NormalFloat's bg,
-- e.g. catppuccin's mantle) kept distinct from Normal, so re-apply it
-- after every colorscheme change.
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

local gutter_group = vim.api.nvim_create_augroup("NvimpagerGutterStyle", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = gutter_group,
  callback = apply_gutter_highlights,
})

vim.defer_fn(function()
  apply_gutter_options()
  apply_gutter_highlights()
  vim.opt.cmdheight = 0
  apply_pager_view()
end, 0)
vim.api.nvim_create_autocmd("User", {
  group = gutter_group,
  pattern = "VeryLazy",
  callback = function()
    apply_gutter_options()
    apply_gutter_highlights()
    vim.opt.cmdheight = 0
    apply_pager_view()
  end,
})
vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter", "BufFilePost" }, {
  group = gutter_group,
  callback = apply_pager_view,
})

-- Max characters in a line highlighted
vim.opt.synmaxcol = 1000

-- Redrawtime
vim.opt.redrawtime = 5000

-- Timeout for keys
vim.opt.timeout = true
vim.opt.timeoutlen = 1000
vim.opt.ttimeoutlen = 10

-- Persist search history across pager invocations via the shada file
-- (default 'shada' omits the "/" item, so no search patterns are saved)
-- We must ensure "'" is present otherwise Neovim throws E528
vim.opt.shada = { "!", "'100", "<50", "s10", "h", "/100" }

-- Neovim's bundled indent/sh.vim ("case-labels") defaults case labels to one
-- extra shiftwidth of indent relative to `case`/`esac` -- combined with the
-- default "case-statements" indent for the body under each label, that adds
-- up to a double indent. b:sh_indent_options is read live by GetShIndent(),
-- so setting "case-labels" to 0 here keeps labels aligned with `case`/`esac`
-- while the body under each label still gets indented once (relevant if a
-- shell script is paged/edited here; nvimpager has no treesitter).
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "sh", "bash" },
  callback = function()
    vim.b.sh_indent_options = { ["case-labels"] = 0 }
  end,
})

-- Detect if nvimpager evaluated this session as "cat mode"
if #vim.api.nvim_list_uis() == 0 then
  -- Force background transparency when not actively paging via the UI.
  local function apply_cat_mode_transparency()
    vim.api.nvim_set_hl(0, "Normal", { bg = "NONE", ctermbg = "NONE" })
    vim.api.nvim_set_hl(0, "NonText", { bg = "NONE", ctermbg = "NONE" })
    vim.api.nvim_set_hl(0, "NormalNC", { bg = "NONE", ctermbg = "NONE" })
  end

  apply_cat_mode_transparency()
  vim.api.nvim_create_autocmd({ "VimEnter", "BufWinEnter", "ColorScheme" }, {
    callback = function()
      apply_gutter_highlights()
      apply_cat_mode_transparency()
    end,
  })
end
