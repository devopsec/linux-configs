local M = {}

-- check if current window has neighboring window
-- direction (1==Top|2==Right|3==Bottom|4==Left)
function M.has_neighbor(direction)
  local current_position = vim.api.nvim_win_get_position(0)
  -- vim.api.nvim_win_get_position returns {row, col} starting from 0, 0
  
  if direction == 1 then
    return current_position[1] ~= 0
  elseif direction == 4 then
    return current_position[2] ~= 0
  end

  local win_nr = vim.api.nvim_list_wins()
  for _, win in ipairs(win_nr) do
    local position = vim.api.nvim_win_get_position(win)
    if direction == 2 and (current_position[2] + vim.api.nvim_win_get_width(0)) < position[2] then
      return true
    elseif direction == 3 and (current_position[1] + vim.api.nvim_win_get_height(0)) < position[1] then
      return true
    end
  end
  return false
end

-- Convert indentations
local function indenting(indent, what, cols)
  local spccol = string.rep(" ", cols)
  local result = indent:gsub(" +\t", "\t")
  -- The original logic in Vim script was 'substitute(result, " \+\ze\t", "", "g")'
  -- which effectively removes spaces before a tab.
  -- In Lua, we can just replace 'spaces followed by tab' with 'tab'.
  if what == 1 then
    result = result:gsub("\t", spccol)
  end
  return result
end

-- indent_convert is simpler to implement using vim.cmd for the substitute part
function M.indent_convert(line1, line2, what, cols)
  local save_pos = vim.fn.getpos(".")
  local c = (cols == nil or cols == "") and vim.bo.tabstop or tonumber(cols)
  
  -- We'll use the function we defined or just use vim.cmd
  -- Better to implement the logic in Lua if we want "native" feel
  -- but for complex regex, Vim script is sometimes easier.
  -- Let's define the Vim script functions for these as they are quite specific.
  vim.cmd(string.format([[
    function! Indenting(indent, what, cols)
      let spccol = repeat(' ', a:cols)
      let result = substitute(a:indent, spccol, '\t', 'g')
      let result = substitute(result, ' \+\ze\t', '', 'g')
      if a:what == 1
        let result = substitute(result, '\t', spccol, 'g')
      endif
      return result
    endfunction
    
    %d,%ds/^\s\+/\=Indenting(submatch(0), %d, %d)/e
  ]], line1, line2, what, c))
  
  vim.fn.histdel("search", -1)
  vim.fn.setpos(".", save_pos)
end

-- Set window resizing mappings based on neighbors
function M.set_win_resize()
  local keymap = vim.keymap.set
  local opts = { silent = true, buffer = true }

  if M.has_neighbor(2) then
    keymap("n", "<A-Left>", ":vertical resize -5<CR>", opts)
    keymap("n", "<A-Right>", ":vertical resize +5<CR>", opts)
  else
    keymap("n", "<A-Left>", ":vertical resize +5<CR>", opts)
    keymap("n", "<A-Right>", ":vertical resize -5<CR>", opts)
  end
  
  if M.has_neighbor(3) then
    keymap("n", "<A-Up>", ":resize -5<CR>", opts)
    keymap("n", "<A-Down>", ":resize +5<CR>", opts)
  elseif M.has_neighbor(1) then
    keymap("n", "<A-Up>", ":resize +5<CR>", opts)
    keymap("n", "<A-Down>", ":resize -5<CR>", opts)
  end
end

-- Set left side margin
function M.set_win_margin()
  if M.has_neighbor(4) then
    vim.opt_local.foldcolumn = "0"
  else
    vim.opt_local.foldcolumn = "1"
  end
end

-- Clear per-window sync options (cursor syncing)
function M.reset_win_sync()
  vim.opt_local.cursorbind = false
  vim.opt_local.scrollbind = false
end

-- Helper for single word command aliases (like :man)
function M.alias(lhs, rhs)
  -- Replace | with <bar> to avoid splitting vim.cmd
  local safe_rhs = rhs:gsub("|", "<bar>")
  local cmd = string.format("cnoreabbrev <expr> %s (getcmdtype() == ':' && getcmdline() =~# '^%s$') ? '%s' : '%s'", lhs, lhs, safe_rhs, lhs)
  vim.cmd(cmd)
end

-- Command aliases
function M.load_command_line_aliases()
  M.alias("man", "Man")
  M.alias("sp", "split")
  M.alias("vs", "vsplit")
  M.alias("term", "vnew|terminal")
  M.alias("hterm", "new|terminal")
  -- For range aliases and others, it might be better to use commands
  vim.api.nvim_create_user_command("Tab", "$tabnew", { range = true })
  M.alias("tab", "Tab")
  M.alias("qq", "tabclose")

  -- Indent conversion commands
  vim.api.nvim_create_user_command("Space2Tab", function(opts)
    M.indent_convert(opts.line1, opts.line2, 0, opts.args)
  end, { range = true, nargs = "?" })

  vim.api.nvim_create_user_command("Tab2Space", function(opts)
    M.indent_convert(opts.line1, opts.line2, 1, opts.args)
  end, { range = true, nargs = "?" })

  vim.api.nvim_create_user_command("RetabIndent", function(opts)
    local et = vim.bo.expandtab and 1 or 0
    M.indent_convert(opts.line1, opts.line2, et, opts.args)
  end, { range = true, nargs = "?" })
end

return M
