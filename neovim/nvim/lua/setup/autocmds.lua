local utils = require("setup.utils")

local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup
local baleia
-- baleia.setup() uses this namespace name by default (see baleia.lua's
-- `either(user_options.name, "BaleiaColors")`); recreating it here (same
-- name -> same id) lets AnsiOff/AnsiToggle clear the highlights without
-- needing a "reset" method, which this baleia.nvim version doesn't expose.
local baleia_namespace = vim.api.nvim_create_namespace("BaleiaColors")

-- Define augroups
local general_group = augroup("GeneralSettings", { clear = true })
local cmdline_group = augroup("CmdlineSettings", { clear = true })
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

-- Load command line aliases
autocmd("VimEnter", {
  group = general_group,
  callback = function()
    utils.load_command_line_aliases()
  end,
})

-- =================================================================================
-- Command-line Mode Behavior
-- =================================================================================

-- Mute hlsearch while typing an Ex command (":..."), but leave it alone for
-- an actual search (invoked as its own cmdtype, "/" or "?") or for a search-
-- like Ex command (:s, :%s, :'<,'>s, :g/.../, :v/.../) -- and restore
-- whatever the user's hlsearch state was beforehand once the command line
-- closes. State is kept in one table, scoped to this `do` block, so it
-- can't be mistaken for file-wide config elsewhere in this file.
do
  local cmdline_search = {
    hlsearch_before_cmdline = true, -- vim.o.hlsearch as it was on CmdlineEnter
    search_intent_resolved = false, -- true once we've locked in a decision past the range-prefix window
  }

  local str_byte = string.byte
  -- Bytes that only ever appear as part of a range specifier (:'<,'>, :10,20,
  -- :.,$, :%), never as the start of a search-like command on their own.
  local non_digit_range_bytes = {
    [str_byte("'")] = true,
    [str_byte(",")] = true,
    [str_byte("$")] = true,
    [str_byte(".")] = true,
    [str_byte("%")] = true,
  }

  local function is_range_prefix_byte(byte)
    return non_digit_range_bytes[byte] or (byte >= 48 and byte <= 57) -- 0-9
  end

  -- Walks past any leading range specifier (bounded to whatever range syntax
  -- was actually typed -- no fixed cutoff, no pattern engine, no keymap
  -- table to scan) and checks whether the first real command character
  -- starts a search-like command: :s, :%s, :'<,'>s, :g/.../, :v/.../.
  local function cmdline_starts_search_pattern(cmdline_text, cmdline_length)
    local i = 1
    while i <= cmdline_length do
      local byte = str_byte(cmdline_text, i)
      if byte == str_byte("s") or byte == str_byte("g") or byte == str_byte("v") then
        return true
      end
      if is_range_prefix_byte(byte) then
        i = i + 1
      else
        return false -- first non-range character isn't a search-like command
      end
    end
    return false
  end

  autocmd("CmdlineEnter", {
    group = cmdline_group,
    callback = function()
      cmdline_search.hlsearch_before_cmdline = vim.o.hlsearch
      cmdline_search.search_intent_resolved = false
      if vim.fn.getcmdtype() == ":" then
        vim.o.hlsearch = false
      end
    end,
  })

  autocmd("CmdlineChanged", {
    group = cmdline_group,
    callback = function()
      if vim.fn.getcmdtype() ~= ":" then
        return
      end
      if cmdline_search.search_intent_resolved then
        return -- shortcut: already decided, nothing left to check
      end

      local cmdline_text = vim.fn.getcmdline()
      local cmdline_length = #cmdline_text
      local is_search = cmdline_starts_search_pattern(cmdline_text, cmdline_length)

      -- Still walking a range specifier: leave the decision open so a
      -- backspace back into range syntax gets re-checked next time too.
      if not is_search and cmdline_length > 0 and is_range_prefix_byte(str_byte(cmdline_text, cmdline_length)) then
        return
      end

      vim.o.hlsearch = is_search and cmdline_search.hlsearch_before_cmdline or false
      cmdline_search.search_intent_resolved = true
    end,
  })

  autocmd("CmdlineLeave", {
    group = cmdline_group,
    callback = function()
      vim.o.hlsearch = cmdline_search.hlsearch_before_cmdline
    end,
  })
end

-- Prevent unmapped function keys from being inserted as literal escape text
-- when typed in the command line (Neovim's default Cmdline-mode behavior
-- for any key without an assigned action). Mapped once, natively, via
-- Neovim's own keymap resolution -- no per-keystroke Lua callback involved.
local function setup_cmdline_noop_keys()
  local cmdline_noop_keys = {}
  for i = 1, 12 do
    cmdline_noop_keys[#cmdline_noop_keys + 1] = "<F" .. i .. ">"
  end

  for _, key in ipairs(cmdline_noop_keys) do
    vim.keymap.set("c", key, "<Nop>", { desc = "Block literal insertion in cmdline: " .. key })
  end
end
setup_cmdline_noop_keys()

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

-- Neovim's bundled indent/sh.vim ("case-labels") defaults case labels to one
-- extra shiftwidth of indent relative to `case`/`esac` -- combined with the
-- default "case-statements" indent for the body under each label, that adds
-- up to a double indent. b:sh_indent_options is read live by GetShIndent(),
-- so setting "case-labels" to 0 here keeps labels aligned with `case`/`esac`
-- while the body under each label still gets indented once.
-- NOTE: this is only a fallback for when the treesitter-based indentexpr
-- isn't active (e.g. the "bash" parser/queries aren't installed yet) --
-- normally bash buffers use the custom indent query in queries/bash/
-- indents.scm instead, which already reproduces this exact style.
autocmd("FileType", {
  group = filetype_group,
  pattern = { "sh", "bash" },
  callback = function()
    vim.b.sh_indent_options = { ["case-labels"] = 0 }
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

