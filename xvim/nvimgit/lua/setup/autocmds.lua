local utils = require("setup.utils")

local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup
local baleia
-- baleia.setup() uses this namespace name by default (see baleia.lua's
-- `either(user_options.name, "BaleiaColors")`); recreating it here (same
-- name -> same id) lets AnsiOff/AnsiToggle clear the highlights without
-- needing a "reset" method, which this baleia.nvim version doesn't expose.
local baleia_namespace = vim.api.nvim_create_namespace("BaleiaColors")

local function get_baleia()
  baleia = baleia or vim.g.baleia or require("baleia").setup({ line_starts_at = 3 })
  return baleia
end

-- General augroup
local general_group = augroup("GeneralSettings", { clear = true })
local plugin_group = augroup("PluginSettings", { clear = true })

-- Make splits auto resize when host resizes
autocmd("VimResized", {
  group = general_group,
  command = "wincmd =",
})

-- Set window margin and resize mappings
autocmd({ "WinEnter", "VimEnter" }, {
  group = general_group,
  callback = function()
    utils.set_win_resize()
  end,
})

-- Set cursor line highlighting
autocmd({ "WinEnter", "VimEnter", "BufWinEnter" }, {
  group = general_group,
  callback = function()
    vim.opt_local.cursorline = true
  end,
})
autocmd({ "WinLeave" }, {
  group = general_group,
  callback = function()
    vim.opt_local.cursorline = false
  end,
})

-- Jump to last position when reopening file
autocmd("BufReadPost", {
  group = general_group,
  callback = function()
    local last_pos = vim.fn.line("'\"")
    if last_pos > 1 and last_pos <= vim.fn.line("$") then
      vim.cmd('normal! g\'"')
    end
  end,
})

-- Disable adding comments when hitting enter
autocmd("FileType", {
  group = general_group,
  callback = function()
    vim.opt_local.formatoptions:remove({ "c", "r", "o" })
  end,
})

-- Load command line aliases
autocmd("VimEnter", {
  group = general_group,
  callback = function()
    utils.load_command_line_aliases()
  end,
})

-- Automatically check for failures and throw a non-zero exit code if running headlessly
if #vim.api.nvim_list_uis() == 0 then
  autocmd("User", {
    group = plugin_group,
    pattern = { "LazyInstall", "LazySync" },
    callback = function()
      local failed = false
      for name, plugin in pairs(require("lazy.core.config").plugins) do
        if plugin._.is_broken then
          failed = true
          io.stderr:write("❌ LazyVim plugin compilation/install failed: " .. name .. "\n")
        end
      end
      if failed then
        vim.cmd("cq") -- Force-quits Neovim immediately with exit code 1
      end
    end,
  })
end

-- Filetype specific settings
autocmd("FileType", {
  group = general_group,
  pattern = "gitcommit",
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.textwidth = 120
  end,
})

autocmd("FileType", {
  group = general_group,
  pattern = "lua",
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
    vim.opt_local.expandtab = true
  end,
})

autocmd("FileType", {
  group = general_group,
  pattern = { "make", "kamailio" },
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = -1
    vim.opt_local.expandtab = false
  end,
})

-- Neovim's bundled indent/sh.vim ("case-labels") defaults case labels to one
-- extra shiftwidth of indent relative to `case`/`esac` -- combined with the
-- default "case-statements" indent for the body under each label, that adds
-- up to a double indent. b:sh_indent_options is read live by GetShIndent(),
-- so setting "case-labels" to 0 here keeps labels aligned with `case`/`esac`
-- while the body under each label still gets indented once.
-- (nvimgit has no treesitter, so this legacy indent script is the only
-- indenter for sh/bash buffers here -- unlike xvim/nvim's custom
-- queries/bash/indents.scm override.)
autocmd("FileType", {
  group = general_group,
  pattern = { "sh", "bash" },
  callback = function()
    vim.b.sh_indent_options = { ["case-labels"] = 0 }
  end,
})

-- Render ANSI escape sequences using Baleia
vim.api.nvim_create_user_command("AnsiOn", function()
  if vim.bo.buftype == "" then
    -- baleia.setup() returns already-curried functions, not OOP methods --
    -- must be called with dot syntax (get_baleia().automatically(buf)), not
    -- colon syntax, which would wrongly pass `baleia` itself as `buffer`
    get_baleia().automatically(vim.api.nvim_get_current_buf())
    vim.b.ansi_enabled = true
  end
end, {})

vim.api.nvim_create_user_command("AnsiOff", function()
  if vim.bo.buftype == "" then
    vim.api.nvim_buf_clear_namespace(vim.api.nvim_get_current_buf(), baleia_namespace, 0, -1)
  end
  vim.b.ansi_enabled = false
end, {})

vim.api.nvim_create_user_command("AnsiToggle", function()
  if vim.bo.buftype ~= "" then
    return
  end

  if vim.b.ansi_enabled then
    vim.api.nvim_buf_clear_namespace(vim.api.nvim_get_current_buf(), baleia_namespace, 0, -1)
    vim.b.ansi_enabled = false
  else
    get_baleia().automatically(vim.api.nvim_get_current_buf())
    vim.b.ansi_enabled = true
  end
end, {})
