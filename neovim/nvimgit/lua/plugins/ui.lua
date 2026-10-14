local function popup_row(offset)
  return math.max(1, math.floor(vim.o.lines / 2) + offset)
end

return {
  -- Keep Telescope and its native sorter out of the nvimgit profile; noice
  -- provides the centered command-line/popup UI needed here.
  { "nvim-telescope/telescope.nvim", enabled = false },
  { "nvim-telescope/telescope-fzf-native.nvim", enabled = false },
  {
    "folke/noice.nvim",
    lazy = false,
    dependencies = { "MunifTanjim/nui.nvim" },
    init = function()
      vim.cmd([[cnoreabbrev <expr> noice getcmdtype() ==# ':' && getcmdline() ==# 'noice' ? 'Noice' : 'noice']])
    end,
    opts = {
      cmdline = {
        enabled = true,
        view = "cmdline_popup",
      },
      messages = {
        view = "mini",
        view_error = "mini",
        view_warn = "mini",
        view_history = "messages",
      },
      notify = {
        view = "mini",
      },
      lsp = {
        message = { view = "mini" },
        progress = { view = "mini" },
      },
      views = {
        cmdline_popup = {
          position = { row = popup_row(-1), col = "50%" },
          size = { min_width = 60, width = 60, height = "auto" },
          border = { style = "rounded", padding = { 0, 1 } },
        },
        cmdline_popupmenu = {
          view = "popupmenu",
          relative = "editor",
          position = { row = popup_row(2), col = "50%" },
          size = { width = 60, height = "auto", max_height = 15 },
          border = { style = "rounded", padding = { 0, 1 } },
          zindex = 210,
          win_options = {
            winhighlight = { Normal = "NoicePopupmenu", FloatBorder = "NoiceCmdlinePopupBorder" },
          },
        },
        mini = {
          position = { row = -2, col = "50%" },
          align = "center",
        },
      },
      routes = {
        {
          view = "popup",
          filter = { event = { "msg_show", "notify" }, min_height = 3 },
        },
      },
      presets = {
        bottom_search = false,
        command_palette = true,
        long_message_to_split = true,
        inc_rename = false,
        lsp_doc_border = true,
      },
    },
  },
  { "folke/tokyonight.nvim", enabled = false },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      transparent_background = false,
      term_colors = true,
      styles = {
        comments = { "italic" },
        conditionals = { "italic" },
      },
      integrations = {
        gitsigns = true,
        mini = true,
        noice = true,
        notify = true,
        treesitter = true,
      },
      custom_highlights = function(colors)
        local gutter_bg = colors.mantle
        return {
          SignColumn = { bg = gutter_bg },
          FoldColumn = { bg = gutter_bg },
          LineNr = { fg = colors.overlay1, bg = gutter_bg },
          LineNrAbove = { fg = colors.overlay1, bg = gutter_bg },
          LineNrBelow = { fg = colors.overlay1, bg = gutter_bg },
          CursorLineNr = { fg = colors.peach, bg = gutter_bg, style = { "bold" } },
          CursorLineSign = { bg = gutter_bg },
          GitSignsAdd = { fg = colors.green, bg = gutter_bg },
          GitSignsChange = { fg = colors.yellow, bg = gutter_bg },
          GitSignsDelete = { fg = colors.red, bg = gutter_bg },
          NormalFloat = { bg = colors.mantle },
        }
      end,
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin-mocha")
    end,
  },
}
