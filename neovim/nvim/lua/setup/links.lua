-- Ctrl+click follows the reference under the mouse and Ctrl+hover underlines
-- it: URLs, manpage references like ls(1), info.nvim cross-references and
-- menu entries, and |tags| in :help buffers. A double-click only selects the
-- word (see after/ftplugin/man.lua and after/ftplugin/help.lua).
--
-- The terminal itself may claim Ctrl+click on the URLs it recognizes (VTE does
-- for http(s), ftp, mailto, ...); every other reference reaches Neovim as
-- <C-LeftMouse>.

local M = {}

local function t(keys)
  return vim.api.nvim_replace_termcodes(keys, true, true, true)
end

local ns = vim.api.nvim_create_namespace("setup.links")

local group = vim.api.nvim_create_augroup("setup.links", { clear = true })

-- underline only, so the reference keeps its own syntax color; a colorscheme
-- change clears it, so define it again
local function define_highlight()
  vim.api.nvim_set_hl(0, "LinkHover", { underline = true, default = true })
end

define_highlight()
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_highlight })

local URL = "%a[%w+.-]*://[^%s<>\"'`|]+"
local MANPAGE = "[%w_][%w_.:+-]*%(%d%w*%)"
local HELP_TAG = "|[^%s|]+|"

-- trailing punctuation (ASCII and UTF-8 closing quotes) that ends a sentence
-- rather than the URL; a ')' or ']' is kept when the URL also opened one
local function trim_url(text)
  local before
  repeat
    before = text
    text = text:gsub("[.,;:!?'\"]$", ""):gsub("’$", ""):gsub("”$", ""):gsub("»$", "")
    if text:sub(-1) == ")" and not text:find("(", 1, true) then
      text = text:sub(1, -2)
    elseif text:sub(-1) == "]" and not text:find("[", 1, true) then
      text = text:sub(1, -2)
    end
  until text == before
  return text
end

-- first match of pattern in line that covers byte col (1-based): start, end
local function match_at(line, pattern, col)
  local init = 1
  while true do
    local s, e = line:find(pattern, init)
    if not s or s > col then
      return nil
    end
    if col <= e then
      return s, e
    end
    init = e + 1
  end
end

local function in_range(row, col, range)
  if row < range.start_row or row > range.end_row then
    return false
  end
  if row == range.start_row and col < range.start_col then
    return false
  end
  return not (row == range.end_row and col >= range.end_col)
end

-- info.nvim's parsed node: the same entries its K/:InfoFollow resolve
local function info_ref(buf, row, col)
  local manual = vim.b[buf]._info_manual
  if not manual then
    return nil
  end
  for _, entries in ipairs({ manual.menu_entries or {}, manual.xreferences or {} }) do
    for _, entry in ipairs(entries) do
      if entry.range and in_range(row, col, entry.range) then
        return { kind = "info", range = entry.range }
      end
    end
  end
end

-- the reference under the mouse, or nil: { kind, buf, range, text }
-- (range is 0-based like extmarks, end_col exclusive)
local function ref_at_mouse()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 or not vim.api.nvim_win_is_valid(pos.winid) then
    return nil
  end
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  local row, col = pos.line - 1, pos.column
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line or col > #line then
    return nil
  end

  local function single(kind, s, e)
    return { kind = kind, buf = buf, text = line:sub(s, e),
             range = { start_row = row, start_col = s - 1, end_row = row, end_col = e } }
  end

  local s, e = match_at(line, URL, col)
  if s then
    local text = trim_url(line:sub(s, e))
    if col < s + #text then
      return single("url", s, s + #text - 1)
    end
  end

  local filetype = vim.bo[buf].filetype
  if filetype == "info" then
    local ref = info_ref(buf, row, col - 1)
    if ref then
      ref.buf = buf
      return ref
    end
  elseif filetype == "help" then
    s, e = match_at(line, HELP_TAG, col)
    if s then
      return single("help", s, e)
    end
  end

  s, e = match_at(line, MANPAGE, col)
  if s then
    return single("man", s, e)
  end
end

local hovered = nil

local function clear_hover()
  if hovered and vim.api.nvim_buf_is_valid(hovered) then
    vim.api.nvim_buf_clear_namespace(hovered, ns, 0, -1)
  end
  hovered = nil
end

local function hover()
  clear_hover()
  local ref = ref_at_mouse()
  if not ref then
    return
  end
  local r = ref.range
  vim.api.nvim_buf_set_extmark(ref.buf, ns, r.start_row, r.start_col, {
    end_row = r.end_row,
    end_col = r.end_col,
    hl_group = "LinkHover",
    priority = 300,
    strict = false,
  })
  hovered = ref.buf
end

local pending = nil

-- runs after <LeftMouse> moved the cursor (and focus) onto the reference
function M.follow()
  local ref = pending
  pending = nil
  if not ref then
    return
  end
  if ref.kind == "url" then
    vim.ui.open(ref.text)
  elseif ref.kind == "info" then
    vim.cmd.InfoFollow()
  elseif ref.kind == "man" then
    -- like K: a split (or the already open manpage window)
    vim.cmd.Man(ref.text)
  end
end

vim.keymap.set("n", "<C-LeftMouse>", function()
  vim.schedule(clear_hover)
  local ref = ref_at_mouse()
  -- :help tags use the native tag jump; elsewhere a miss only moves the
  -- cursor instead of failing a :tag lookup
  if not ref or ref.kind == "help" then
    return t(ref and "<C-LeftMouse>" or "<LeftMouse>")
  end
  pending = ref
  return t("<LeftMouse><Cmd>lua require('setup.links').follow()<CR>")
end, { expr = true, silent = true, replace_keycodes = false, desc = "Follow the reference under the mouse" })

-- mouse move events are only delivered (and mappable) with 'mousemoveevent';
-- an unmodified move clears the underline again
vim.o.mousemoveevent = true
vim.keymap.set("n", "<C-MouseMove>", hover, { silent = true, desc = "Underline the reference under the mouse" })
vim.keymap.set("n", "<MouseMove>", function()
  if hovered then
    clear_hover()
  end
end, { silent = true })

vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled", "BufLeave", "ModeChanged" }, {
  group = group,
  callback = function()
    if hovered then
      clear_hover()
    end
  end,
})

return M
