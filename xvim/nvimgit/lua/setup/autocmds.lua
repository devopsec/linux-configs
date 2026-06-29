local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup
local baleia

local function get_baleia()
  baleia = baleia or vim.g.baleia or require("baleia").setup({ line_starts_at = 3 })
  return baleia
end

-- General augroup
local general_group = augroup("GeneralSettings", { clear = true })

-- Make splits auto resize when host resizes
autocmd("VimResized", {
  group = general_group,
  command = "wincmd =",
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
