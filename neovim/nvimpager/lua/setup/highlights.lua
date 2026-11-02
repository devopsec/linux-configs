-- Theme-agnostic popup/menu/console highlights: opaque backgrounds distinct
-- from Normal and per-window border colours, derived from the active
-- colorscheme so they survive colorscheme switches.

local function get_hl(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local function to_rgb(n)
  return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
end

local function to_int(r, g, b)
  local function clamp(v)
    return math.max(0, math.min(255, math.floor(v + 0.5)))
  end
  return clamp(r) * 65536 + clamp(g) * 256 + clamp(b)
end

-- darken (pct < 0) or lighten (pct > 0) a 24-bit colour
local function shade(n, pct)
  local r, g, b = to_rgb(n)
  local function mix(v)
    if pct < 0 then
      return v * (1 + pct)
    end
    return v + (255 - v) * pct
  end
  return to_int(mix(r), mix(g), mix(b))
end

local function is_dark(n)
  local r, g, b = to_rgb(n)
  return (0.299 * r + 0.587 * g + 0.114 * b) < 128
end

local function fg_of(names, fallback)
  for _, name in ipairs(names) do
    local fg = get_hl(name).fg
    if fg then
      return fg
    end
  end
  return fallback
end

local function apply_popup_highlights()
  local normal = get_hl("Normal")
  local base = normal.bg or (vim.o.background == "dark" and 0x1e1e1e or 0xf5f5f5)
  local text = normal.fg or (is_dark(base) and 0xf5f5f5 or 0x202020)
  local popup_bg = is_dark(base) and shade(base, -0.35) or shade(base, -0.07)
  local sel_bg = fg_of({ "Function", "Directory" }, 0x61afef)
  local sel_fg = is_dark(sel_bg) and 0xffffff or 0x101010

  local border_cmd = sel_bg
  local border_search = fg_of({ "String", "DiagnosticOk" }, 0x98c379)
  local border_console = fg_of({ "Constant", "DiagnosticWarn", "WarningMsg" }, 0xe5c07b)
  local border_menu = fg_of({ "Comment", "NonText" }, 0x808080)
  local sbar_bg = shade(popup_bg, is_dark(popup_bg) and 0.12 or -0.1)
  local thumb_bg = shade(popup_bg, is_dark(popup_bg) and 0.4 or -0.4)

  local function set(name, val)
    val.default = nil
    vim.api.nvim_set_hl(0, name, val)
  end

  set("NormalFloat", { fg = text, bg = popup_bg })
  set("FloatBorder", { fg = border_menu, bg = popup_bg })
  set("Pmenu", { fg = text, bg = popup_bg })
  set("PmenuSel", { fg = sel_fg, bg = sel_bg, bold = true })
  set("PmenuSbar", { bg = sbar_bg })
  set("PmenuThumb", { bg = thumb_bg })
  set("WildMenu", { fg = sel_fg, bg = sel_bg, bold = true })

  set("NoiceCmdlinePopup", { fg = text, bg = popup_bg })
  set("NoiceCmdlinePopupBorder", { fg = border_cmd, bg = popup_bg })
  set("NoiceCmdlinePopupBorderSearch", { fg = border_search, bg = popup_bg })
  set("NoiceCmdlinePopupTitle", { fg = border_cmd, bg = popup_bg, bold = true })
  set("NoicePopupmenu", { fg = text, bg = popup_bg })
  set("NoicePopupmenuSelected", { fg = sel_fg, bg = sel_bg, bold = true })
  set("NoicePopupmenuBorder", { fg = border_menu, bg = popup_bg })
  set("NoicePopup", { fg = text, bg = popup_bg })
  set("NoicePopupBorder", { fg = border_console, bg = popup_bg })
  set("NoiceMini", { fg = text, bg = popup_bg })
  set("NoiceConsoleBorder", { fg = border_console, bg = popup_bg })
end

apply_popup_highlights()

local group = vim.api.nvim_create_augroup("PopupHighlights", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = apply_popup_highlights,
})
-- noice defines its own groups on VeryLazy/setup; re-apply once it has loaded
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = "VeryLazy",
  callback = apply_popup_highlights,
})
