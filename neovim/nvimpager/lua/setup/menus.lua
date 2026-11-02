-- Popup menu key handling shared by the insert-mode completion menu, the
-- command-line (wildmenu) completion menu and the right-click PopUp menu.
--
-- Every mapping is an <expr> mapping that returns keys: the PopUp menu loop
-- only reacts to real keycodes (never to Lua callbacks), and the wildmenu
-- relies on its own key translation (<Up>/<Down> descend/ascend directories,
-- <C-N>/<C-P> move the selection, <C-Y> accepts, <C-E> cancels).
--
-- noice.nvim renders all three menus (ext_popupmenu); its state is the only
-- way to know which command-line / PopUp entry is highlighted and where the
-- menu window is on screen (mouse clicks). Without it the mappings fall back
-- to Neovim's native behavior.

local function t(keys)
  return vim.api.nvim_replace_termcodes(keys, true, true, true)
end

local expropts = { expr = true, silent = true, replace_keycodes = false }

-- maps lhs to the keys returned by fn(); nil means "behave natively"
local function map(modes, lhs, fn)
  vim.keymap.set(modes, lhs, function()
    return t(fn() or lhs)
  end, expropts)
end

local function noice_state()
  local pum = package.loaded["noice.ui.popupmenu"]
  return pum and pum.state.visible and pum.state or nil
end

local function noice_menu_win()
  local nui = package.loaded["noice.ui.popupmenu.nui"]
  local win = nui and nui.menu and nui.menu.winid
  return win and vim.api.nvim_win_is_valid(win) and win or nil
end

-- "insert" (completion menu), "cmdline" (wildmenu), "popup" (right-click
-- PopUp menu, shown from normal/visual/insert mode) or nil when no menu is open
local function menu_kind()
  if vim.fn.pumvisible() == 0 then
    return nil
  end
  local mode = vim.fn.mode()
  if mode == "c" then
    return "cmdline"
  end
  if mode:sub(1, 1) == "i" and vim.fn.complete_info({ "mode" }).mode ~= "" then
    return "insert"
  end
  return "popup"
end

-- zero-based index of the highlighted entry, -1 when nothing is highlighted
local function selected(kind)
  if kind == "insert" then
    return vim.fn.complete_info({ "selected" }).selected
  end
  local state = noice_state()
  return state and state.selected or -1
end

local function menu_size()
  return math.floor(vim.fn.pum_getpos().size or 0)
end

-- entries per menu page (like native <PageUp>/<PageDown>: height minus context)
local function page_size()
  local win = noice_menu_win()
  local height = win and vim.api.nvim_win_get_height(win) or math.floor(vim.fn.pum_getpos().height or 0)
  return math.max(1, height > 3 and height - 2 or height)
end

-- highlights (insert=false) or fills in (insert=true) the entry at idx;
-- finish=true also accepts it and closes the menu
local function select_item(idx, insert, finish)
  return string.format(
    "<Cmd>call nvim_select_popupmenu_item(%d, v:%s, v:%s, {})<CR>",
    idx, insert and "true" or "false", finish and "true" or "false"
  )
end

-- PopUp menu: number of <Up>/<Down> presses to move the highlight from entry
-- `from` to entry `to` (separator entries are skipped by the menu itself)
local function popup_steps(state, from, to)
  local key, step = "<Down>", 1
  if to < from then
    key, step = "<Up>", -1
  end
  local presses = 0
  for i = from + step, to, step do
    if state.items[i + 1].word ~= "" then
      presses = presses + 1
    end
  end
  return string.rep(key, presses)
end

-- left click on an entry of the noice menu window accepts that entry
local function click_accept(kind)
  local win = noice_menu_win()
  if not win then
    return nil
  end
  local pos = vim.fn.getmousepos()
  if pos.winid ~= win or pos.line == 0 then
    return nil
  end
  local idx = pos.line - 1
  if kind ~= "popup" then
    return select_item(idx, true, true)
  end
  local state = noice_state()
  if not state or not state.items[idx + 1] or state.items[idx + 1].word == "" then
    return nil
  end
  return popup_steps(state, state.selected, idx) .. "<CR>"
end

-- ---------------------------------------------------------------------------
-- insert mode (completion menu / PopUp) and normal/visual mode (PopUp)
-- ---------------------------------------------------------------------------

local popup_modes = { "n", "x", "i" }

-- <Home>|<End> to highlight the first/last menu entry
map(popup_modes, "<Home>", function()
  local kind = menu_kind()
  if kind == "insert" then
    return select_item(0, false, false)
  elseif kind == "popup" then
    return string.rep("<Up>", menu_size())
  end
end)
map(popup_modes, "<End>", function()
  local kind = menu_kind()
  if kind == "insert" then
    return select_item(menu_size() - 1, false, false)
  elseif kind == "popup" then
    return string.rep("<Down>", menu_size())
  end
end)

-- <PageUp>|<PageDown> to move the highlight one menu page up/down (native for
-- the completion menu)
map(popup_modes, "<PageUp>", function()
  if menu_kind() == "popup" then
    return string.rep("<Up>", page_size())
  end
end)
map(popup_modes, "<PageDown>", function()
  if menu_kind() == "popup" then
    return string.rep("<Down>", page_size())
  end
end)

-- left click on a menu entry accepts it
map(popup_modes, "<LeftMouse>", function()
  local kind = menu_kind()
  if kind then
    return click_accept(kind)
  end
end)

-- mouse wheel moves the completion menu highlight instead of scrolling the
-- buffer (the PopUp menu handles the wheel itself)
map("i", "<ScrollWheelUp>", function()
  if menu_kind() == "insert" then
    return "<Up>"
  end
end)
map("i", "<ScrollWheelDown>", function()
  if menu_kind() == "insert" then
    return "<Down>"
  end
end)

-- <Tab> fills in the highlighted completion without accepting it (the menu
-- stays open); with nothing highlighted it highlights the first entry
map("i", "<Tab>", function()
  local kind = menu_kind()
  if kind == "insert" then
    local idx = selected(kind)
    return idx >= 0 and select_item(idx, true, false) or "<Down>"
  elseif kind == "popup" then
    return ""
  end
end)

-- <S-Tab> does nothing inside menus, un-indents otherwise
map("i", "<S-Tab>", function()
  return menu_kind() and "" or "<C-D>"
end)

-- <CR> accepts the highlighted completion; otherwise behaves natively
-- (mini.pairs skips its own <CR> mapping when one already exists)
map("i", "<CR>", function()
  local kind = menu_kind()
  if kind == "insert" and selected(kind) >= 0 then
    return "<C-Y>"
  elseif kind == nil and _G.MiniPairs then
    return _G.MiniPairs.cr()
  end
end)

-- <Esc> closes the completion menu without leaving insert mode
map("i", "<Esc>", function()
  if menu_kind() == "insert" then
    return "<C-E>"
  end
end)

-- ---------------------------------------------------------------------------
-- command-line mode (wildmenu)
-- ---------------------------------------------------------------------------

local function wildmenu()
  return vim.fn.wildmenumode() == 1
end

-- true when the highlighted entry can be descended into (directory / submenu),
-- false when the completion is hierarchical but the entry is a leaf, nil when
-- the completion type has no hierarchy at all
local function submenu_dir()
  local ctype = vim.fn.getcmdcompltype()
  local line, pos = vim.fn.getcmdline(), vim.fn.getcmdpos()
  local last = line:sub(pos - 1, pos - 1)
  if ctype == "menu" then
    return last == "."
  elseif ctype == "file" or ctype == "dir" or ctype == "shellcmd" then
    return last == "/"
  end
  return nil
end

-- mouse wheel moves the highlight; outside the menu it is ignored instead of
-- being turned into history browsing
map("c", "<ScrollWheelUp>", function()
  return wildmenu() and "<C-P>" or ""
end)
map("c", "<ScrollWheelDown>", function()
  return wildmenu() and "<C-N>" or ""
end)

-- <Up>|<Down> move the highlight (natively they browse the history)
map("c", "<Up>", function()
  if wildmenu() then
    return "<C-P>"
  end
end)
map("c", "<Down>", function()
  if wildmenu() then
    return "<C-N>"
  end
end)

-- <Right>|<Left> descend into / ascend out of the highlighted directory or
-- submenu; no action for flat completions (natively they move the highlight)
map("c", "<Right>", function()
  if wildmenu() then
    return submenu_dir() and "<Down>" or ""
  end
end)
map("c", "<Left>", function()
  if wildmenu() then
    return submenu_dir() ~= nil and "<Up>" or ""
  end
end)

-- <Tab> starts completion ('wildcharm' stands in for the typed 'wildchar');
-- once an entry is highlighted its text is already filled in, so <Tab> does
-- nothing instead of cycling to the next entry
map("c", "<Tab>", function()
  if vim.fn.getcmdtype() ~= ":" then
    return nil
  end
  if wildmenu() and selected("cmdline") >= 0 then
    return ""
  end
  return "<C-Z>"
end)

-- <S-Tab> does nothing inside the menu (natively it cycles backwards)
map("c", "<S-Tab>", function()
  if wildmenu() then
    return ""
  end
end)

-- <CR> accepts the highlighted entry and keeps editing the command line;
-- without a highlighted entry it executes the command as usual
map("c", "<CR>", function()
  if wildmenu() and selected("cmdline") >= 0 then
    return "<C-Y>"
  end
end)

-- <Home>|<End> highlight the first/last menu entry
map("c", "<Home>", function()
  if wildmenu() then
    return select_item(0, true, false)
  end
end)
map("c", "<End>", function()
  if wildmenu() then
    return select_item(menu_size() - 1, true, false)
  end
end)

-- left click on a menu entry accepts it
map("c", "<LeftMouse>", function()
  if wildmenu() then
    return click_accept("cmdline")
  end
end)

-- ---------------------------------------------------------------------------
-- command-line file completion: drop the backslash escaping of characters
-- that are not special for :edit & co (' always, ! unless it starts a word)
-- ---------------------------------------------------------------------------

local unescape_types = { file = true, dir = true, file_in_path = true, dir_in_path = true }

local function unescape(text)
  return (text:gsub("()\\([!'])", function(pos, ch)
    if ch == "'" or (pos > 1 and not text:sub(pos - 1, pos - 1):match("[%s\\]")) then
      return ch
    end
  end))
end

local unescaping = false

local function unescape_cmdline()
  if unescaping or not unescape_types[vim.fn.getcmdcompltype()] then
    return
  end
  local line, pos = vim.fn.getcmdline(), vim.fn.getcmdpos()
  if not line:find("\\[!']") then
    return
  end
  local before = unescape(line:sub(1, pos - 1))
  unescaping = true
  vim.fn.setcmdline(before .. unescape(line:sub(pos)), #before + 1)
  unescaping = false
end

-- Editing the command line while a completion is in progress corrupts its
-- state (even when the menu is not shown, e.g. after the 'longest' step), so
-- the text is only touched right after a key that is known to end the
-- completion: a typed character or a plain deletion.
local plain_keys = {
  [t("<BS>")] = true,
  [t("<C-H>")] = true,
  [t("<Del>")] = true,
  [t("<C-W>")] = true,
  [t("<C-U>")] = true,
}

local function is_plain_key(key)
  if plain_keys[key] then
    return true
  end
  return vim.fn.strcharlen(key) == 1 and key:byte() >= 32 and key:byte() ~= 127
end

local keyns = vim.api.nvim_create_namespace("setup.menus.cmdline")
local last_key = ""
local group = vim.api.nvim_create_augroup("setup.menus.cmdline", { clear = true })

vim.api.nvim_create_autocmd("CmdlineEnter", {
  group = group,
  pattern = ":",
  callback = function()
    last_key = ""
    vim.on_key(function(key)
      last_key = key
    end, keyns)
  end,
})

vim.api.nvim_create_autocmd("CmdlineChanged", {
  group = group,
  pattern = ":",
  callback = function()
    if is_plain_key(last_key) then
      unescape_cmdline()
    end
  end,
})

vim.api.nvim_create_autocmd("CmdlineLeave", {
  group = group,
  pattern = ":",
  callback = function()
    vim.on_key(nil, keyns)
    if not vim.v.event.abort then
      unescape_cmdline()
    end
  end,
})
