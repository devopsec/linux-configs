-- which-key.nvim tweaks shared by nvim and nvimpager:
--
-- * hydra mode: the <leader> menu stays open after running a mapping (it
--   reopens at <leader>) until <Esc>; keys without a mapping are ignored
-- * navigation: <Down>/<Up> and <PageDown>/<PageUp> scroll (like <C-d>/<C-u>)
--   and <Left> goes back a level (like <BS>), unless the group maps that key
-- * readability: a wide, centered multi-column layout and an icon for every
--   group and common action
--
-- The hydra and navigation keys hook which-key's internal state module
-- (which-key.state), so they depend on the pinned which-key revision.

local M = {}

-- checked before which-key's own rules (Lua patterns, matched against the
-- lowercased description, then the plugin name); colors are which-key's
-- WhichKeyColor* groups
local rules = {
  { pattern = "which%-key", icon = "󰌌 ", color = "purple" },
  { pattern = "keymap", icon = "󰌌 ", color = "purple" },
  { pattern = "split.*below", icon = "󰤻 ", color = "blue" },
  { pattern = "split.*right", icon = "󰤼 ", color = "blue" },
  { pattern = "keywordprg", icon = "󰋖 ", color = "azure" },
  { pattern = "help", icon = "󰋖 ", color = "azure" },
  { pattern = "man ?page", icon = "󰗚 ", color = "azure" },
  { pattern = "info", icon = "󰋼 ", color = "azure" },
  { pattern = "changelog", icon = "󰦪 ", color = "azure" },
  { pattern = "^lazy$", icon = "󰒲 ", color = "azure" },
  { pattern = "plugin", icon = "󰏗 ", color = "azure" },
  { pattern = "delete", icon = "󰆴 ", color = "red" },
  { pattern = "close", icon = "󰅖 ", color = "red" },
  { pattern = "quit", icon = "󰈆 ", color = "red" },
  { pattern = "other buffer", icon = "󰬲 ", color = "cyan" },
  { pattern = "new tab", icon = "󰝜 ", color = "purple" },
  { pattern = "next", icon = "󰒭 ", color = "purple" },
  { pattern = "previous", icon = "󰒮 ", color = "purple" },
  { pattern = "first", icon = "󰒫 ", color = "purple" },
  { pattern = "last", icon = "󰒬 ", color = "purple" },
  { pattern = "new file", icon = "󰝒 ", color = "green" },
  { pattern = "wrap", icon = "󰖶 ", color = "yellow" },
  { pattern = "relative", icon = "󰉻 ", color = "yellow" },
  { pattern = "number", icon = "󰎠 ", color = "yellow" },
  { pattern = "spell", icon = "󰓆 ", color = "yellow" },
  { pattern = "conceal", icon = "󰈉 ", color = "yellow" },
  { pattern = "background", icon = "󰔎 ", color = "yellow" },
  { pattern = "cursor ?line", icon = "󰘤 ", color = "yellow" },
  { pattern = "highlight", icon = "󰸱 ", color = "yellow" },
  { pattern = "redraw", icon = "󰑓 ", color = "yellow" },
  { pattern = "inspect", icon = "󰙅 ", color = "cyan" },
  { pattern = "word", icon = "󰬴 ", color = "green" },
  { pattern = "quickfix", icon = "󰁨 ", color = "green" },
  { pattern = "location", icon = "󰆋 ", color = "green" },
  { pattern = "symbol", icon = "󰅩 ", color = "orange" },
  { pattern = "rename", icon = "󰑕 ", color = "orange" },
  { pattern = "action", icon = "󰌵 ", color = "orange" },
  { pattern = "blame", icon = "󰊢 ", color = "orange" },
  { pattern = "browse", icon = "󰖟 ", color = "orange" },
  { pattern = "git", icon = "󰊢 ", color = "orange" },
  { pattern = "zoom", icon = "󰊓 ", color = "cyan" },
  { pattern = "zen", icon = "󱅻 ", color = "cyan" },
}

-- merges the layout/icon options into the plugin opts table
function M.opts(opts)
  opts.preset = "modern"
  opts.win = vim.tbl_deep_extend("force", opts.win or {}, {
    border = "rounded",
    padding = { 1, 2 },
    title = true,
    title_pos = "center",
    wo = { winblend = 0 },
  })
  opts.layout = vim.tbl_deep_extend("force", opts.layout or {}, {
    width = { min = 28, max = 44 },
    spacing = 4,
  })
  opts.icons = vim.tbl_deep_extend("force", opts.icons or {}, {
    breadcrumb = "»",
    separator = "→",
    group = "+",
  })
  opts.icons.rules = vim.list_extend(vim.deepcopy(rules), opts.icons.rules or {})
  return opts
end

-- installs the hydra mode and the extra navigation keys (after setup())
function M.patch()
  local Config = require("which-key.config")
  local State = require("which-key.state")
  local Util = require("which-key.util")

  local leader = Util.norm("<leader>")
  local start = State.start
  State.start = function(opts)
    if opts and opts.loop == nil and opts.keys and Util.norm(opts.keys) == leader then
      opts.loop = true
    end
    return start(opts)
  end

  local alias = {
    ["<Down>"] = Config.keys.scroll_down,
    ["<PageDown>"] = Config.keys.scroll_down,
    ["<Up>"] = Config.keys.scroll_up,
    ["<PageUp>"] = Config.keys.scroll_up,
    ["<Left>"] = "<BS>",
  }
  local own = { ["<Esc>"] = true, ["<BS>"] = true }
  local check = State.check
  State.check = function(state, key)
    if key and not state.node:find(key, { expand = true }) then
      key = alias[key] or key
      -- hydra: a key without a mapping would be fed back and reopen the menu
      -- in a loop, so it is ignored instead
      if state.filter.loop and not own[key] and key ~= Config.keys.scroll_down and key ~= Config.keys.scroll_up then
        return state.node
      end
    end
    return check(state, key)
  end
end

return M
