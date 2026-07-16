local utils = require("setup.utils")

local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup
local baleia

-- Performance Cache: Tracks the last known line count for each open buffer
local last_line_counts = {}

-- Define augroups
local general_group = augroup("GeneralSettings", { clear = true })
local plugin_group = augroup("PluginSettings", { clear = true })
local filetype_group = augroup("FiletypeSettings", { clear = true })

local function get_baleia()
  baleia = baleia or vim.g.baleia or require("baleia").setup({ line_starts_at = 3 })
  return baleia
end

-- =================================================================================
-- General Settings
-- =================================================================================

-- Make splits auto resize when host resizes
autocmd("VimResized", {
  group = general_group,
  command = "wincmd =",
})

-- Set window margin and resize mappings
autocmd({ "WinEnter", "VimEnter" }, {
  group = general_group,
  callback = function()
    --utils.reset_win_sync()
    --utils.set_win_margin()
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

-- Force Neovim to redraw gutter when making live changes
-- Makes changes to statuscolumn/linenumbers/signs instant
autocmd({ "TextChangedI", "InsertEnter" }, {
  group = general_group,
  pattern = "*",
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local current_lines = vim.api.nvim_buf_line_count(bufnr)

    if last_line_counts[bufnr] == current_lines then
      return
    end

    last_line_counts[bufnr] = current_lines
    vim.cmd("redraw!")
  end,
})

-- Load command line aliases
autocmd("VimEnter", {
  group = general_group,
  callback = function()
    utils.load_command_line_aliases()
  end,
})

-- =================================================================================
-- Plugin Related Settings
-- =================================================================================

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

-- Update lualine on focus change
--autocmd({ "WinClosed", "WinEnter", "BufEnter" }, {
--  group = plugin_group,
--  callback = function()
--    vim.cmd("redrawtabline")
--    require('lualine').refresh()
--  end,
--})

-- =================================================================================
-- Per-FileType Settings
-- =================================================================================

autocmd("FileType", {
  group = filetype_group,
  pattern = "gitcommit",
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.textwidth = 120
  end,
})

autocmd("FileType", {
  group = filetype_group,
  pattern = { "json", "json5", "lua" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
    vim.opt_local.expandtab = true
  end,
})

autocmd("FileType", {
  group = filetype_group,
  pattern = { "make", "kamailio" },
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = -1
    vim.opt_local.expandtab = false
  end,
})

-- Open pandoc for doc/docx etc...
autocmd("BufReadPost", {
  group = filetype_group,
  pattern = { "*.doc", "*.docx", "*.rtf", "*.odp", "*.odt" },
  callback = function()
    local path = vim.fn.expand("%:p")
    local output = vim.fn.system({ "pandoc", path, "-tplain" })
    if vim.v.shell_error == 0 then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output, "\n"))
    end
  end,
})

-- Read-only pdf through pdftotext
autocmd("BufReadPre", {
  group = filetype_group,
  pattern = "*.pdf",
  callback = function()
    vim.opt_local.readonly = true
  end,
})
autocmd("BufReadPost", {
  group = filetype_group,
  pattern = "*.pdf",
  callback = function()
    local path = vim.fn.expand("%:p")
    -- We can't use a table for pdftotext because of the pipe to fmt.
    -- However, we can use pdftotext's -width option instead of piping to fmt
    -- or just avoid fmt if possible.
    -- Better yet, we can run pdftotext and then use Lua to format the output.
    local output = vim.fn.system({ "pdftotext", "-nopgbrk", "-layout", "-q", "-eol", "unix", path, "-" })
    if vim.v.shell_error == 0 then
      -- Simple line wrap in Lua if needed, but pdftotext -layout usually handles things well.
      -- If fmt is strictly necessary, we can use a safer shell execution.
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output, "\n"))
    end
  end,
})

-- =================================================================================
-- User Command Definitions
-- =================================================================================

-- Render ANSI escape sequences using Baleia
vim.api.nvim_create_user_command("AnsiOn", function()
  if vim.bo.buftype == "" then
    get_baleia():automatically(vim.api.nvim_get_current_buf())
    vim.b.ansi_enabled = true
  end
end, {})

vim.api.nvim_create_user_command("AnsiOff", function()
  if vim.bo.buftype == "" and baleia then
    baleia:reset(vim.api.nvim_get_current_buf())
  end
  vim.b.ansi_enabled = false
end, {})

vim.api.nvim_create_user_command("AnsiToggle", function()
  if vim.bo.buftype ~= "" then
    return
  end

  if vim.b.ansi_enabled then
    if baleia then
      baleia:reset(vim.api.nvim_get_current_buf())
    end
    vim.b.ansi_enabled = false
  else
    get_baleia():automatically(vim.api.nvim_get_current_buf())
    vim.b.ansi_enabled = true
  end
end, {})
