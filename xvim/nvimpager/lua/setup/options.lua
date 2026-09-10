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

-- Default split created below / right
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Space between vertical splits
vim.opt.fillchars:append({ vert = " " })

-- Enable 24bit True Color
vim.opt.termguicolors = true

-- Always show the status bar
vim.opt.laststatus = 3

-- Max characters in a line highlighted
vim.opt.synmaxcol = 1000

-- Redrawtime
vim.opt.redrawtime = 5000

-- Timeout for keys
vim.opt.timeout = true
vim.opt.timeoutlen = 1000
vim.opt.ttimeoutlen = 0

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
  -- force background transparency when not actively "paging" via the UI
  vim.api.nvim_create_autocmd({ "VimEnter", "BufWinEnter", "ColorScheme" }, {
    callback = function()
      -- Setting bg to 'NONE' forces Neovim to look through to the terminal
      vim.api.nvim_set_hl(0, "Normal", { bg = "NONE", ctermbg = "NONE" })
      vim.api.nvim_set_hl(0, "NonText", { bg = "NONE", ctermbg = "NONE" })
      vim.api.nvim_set_hl(0, "NormalNC", { bg = "NONE", ctermbg = "NONE" })
    end,
  })
end
