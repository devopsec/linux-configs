local function popup_row(offset)
  return math.max(1, math.floor(vim.o.lines / 2) + offset)
end

return {
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim" },
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
          win_options = {
            winblend = 0,
            winhighlight = { Normal = "NoiceCmdlinePopup", FloatBorder = "NoiceCmdlinePopupBorder" },
          },
        },
        cmdline_popupmenu = {
          view = "popupmenu",
          relative = "editor",
          position = { row = popup_row(2), col = "50%" },
          size = { width = 60, height = "auto", max_height = 15 },
          border = { style = "rounded", padding = { 0, 1 } },
          zindex = 210,
          win_options = {
            winblend = 0,
            winhighlight = { Normal = "NoicePopupmenu", FloatBorder = "NoicePopupmenuBorder" },
          },
        },
        -- bottom-centered dialog above the statusline for installer progress
        -- (nvim-treesitter); oldest line first so new lines append at the bottom
        ts_progress = {
          backend = "mini",
          relative = "editor",
          timeout = 4000,
          reverse = false,
          focusable = false,
          align = "message-left",
          position = { row = -3, col = "50%" },
          size = { width = 72, height = "auto", max_height = 12 },
          border = { style = "rounded", padding = { 0, 1 } },
          zindex = 60,
          win_options = {
            winblend = 0,
            winhighlight = { Normal = "NoicePopup", FloatBorder = "NoicePopupBorder" },
          },
        },
        mini = {
          position = { row = -3, col = "50%" },
          align = "center",
          border = { style = "rounded", padding = { 0, 1 } },
          win_options = {
            winblend = 0,
            winhighlight = { Normal = "NoiceCmdlinePopup", FloatBorder = "NoiceConsoleBorder" },
          },
        },
        popup = {
          border = { style = "rounded", padding = { 0, 1 } },
          win_options = {
            winblend = 0,
            winhighlight = { Normal = "NoiceCmdlinePopup", FloatBorder = "NoiceConsoleBorder" },
          },
        },
        messages = {
          border = { style = "rounded", padding = { 0, 1 } },
          win_options = {
            winblend = 0,
            winhighlight = { Normal = "NoiceCmdlinePopup", FloatBorder = "NoiceConsoleBorder" },
          },
        },
      },
      routes = {
        {
          view = "ts_progress",
          filter = { event = "msg_show", find = "^%[nvim%-treesitter" },
        },
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
  -- Keep TokyoNight out of the plugin graph so LazyVim never tries to load it.
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
      color_overrides = {
        -- "Catppuccin Coffee": grey-neutral mocha
        mocha = {
          text = "#f5f5f5",
          subtext1 = "#dedede",
          subtext0 = "#c7c7c7",
          overlay2 = "#b3b3b3",
          overlay1 = "#9c9c9c",
          overlay0 = "#878787",
          surface2 = "#707070",
          surface1 = "#595959",
          surface0 = "#454545",
          base = "#2e2e2e",
          mantle = "#262626",
          crust = "#1c1c1c",
        },
      },
      styles = {
        comments = { "italic" },
        conditionals = { "italic" },
        keywords = { "italic" },
        booleans = { "bold" },
      },
      integrations = {
        cmp = true,
        gitsigns = true,
        indent_blankline = { enabled = true },
        lsp_trouble = true,
        mason = true,
        mini = true,
        native_lsp = { enabled = true },
        noice = true,
        notify = true,
        nvimtree = true,
        treesitter = true,
        which_key = true,
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
        }
      end,
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin-mocha")
    end,
  },
  {
    'nvim-lualine/lualine.nvim',
    event = "VeryLazy",
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      require('lualine').setup({
        options = {
          theme = 'powerline',
          -- Flat, square-cornered bar flush with the terminal edges: no
          -- rounded end-caps or separators anywhere in the bottom bar.
          component_separators = { left = '', right = '' },
          section_separators = { left = '', right = '' },
          icons_enabled = true,
          disabled_filetypes = {
            statusline = { "NvimTree", "netrw" },
            winbar = {},
          },
          always_divide_middle = true,
          globalstatus = true,
          refresh = {
            statusline = 300,
            tabline = 1000,
            winbar = 1000,
          }
        },
        -- BOTTOM BAR
        -- general file info
        sections = {
          lualine_a = { 'mode' },
          lualine_b = { 'branch', 'diff', 'diagnostics' },
          lualine_c = { 'filename' },
          lualine_x = { 'encoding', 'fileformat', 'filetype' },
          lualine_y = { 'progress' },
          lualine_z = { 'location' },
        },
        -- TOP BAR
        -- tabs / windows (splits) / buffers (vsplits)
        tabline = {
          lualine_a = { 'tabs' },
          lualine_b = {},
          lualine_c = {},
          lualine_x = {},
          lualine_y = {},
          lualine_z = {}
        },
        --winbar = {
        --  lualine_a = {},
        --  lualine_b = {},
        --  lualine_c = { 'filename' },
        --  lualine_x = {},
        --  lualine_y = {},
        --  lualine_z = {}
        --},
        --inactive_winbar = {
        --  lualine_a = {},
        --  lualine_b = {},
        --  lualine_c = { 'filename' },
        --  lualine_x = {},
        --  lualine_y = {},
        --  lualine_z = {}
        --}
      })
    end,
  },
  {
    "nvim-tree/nvim-tree.lua",
    version = "*", -- Pin to the latest stable release
    cmd = { "NvimTreeToggle", "NvimTreeFocus", "NvimTreeOpen", "NvimTreeFindFile" }, -- Load on demand only
    init = function()
      -- preserve the "open with a directory argument" startup flow (`nvim .`)
      -- even though nvim-tree no longer loads unconditionally at startup
      if vim.fn.argc(-1) == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 then
        vim.cmd("NvimTreeOpen " .. vim.fn.argv(0))
      end
    end,
    dependencies = { "nvim-tree/nvim-web-devicons" }, -- Recommended for icons
    config = function()
      -- Configure nvim-tree
      require("nvim-tree").setup({
        -- Add custom options here, e.g., git decoration
        git = { enable = true },
      })
    end,
  },
  {
    "NvChad/nvim-colorizer.lua",
    ft = { "css", "scss", "less", "html", "lua", "conf", "config", "vim" },
    config = function()
      require("colorizer").setup()
    end,
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    -- v3 requires the main entry point module to be "ibl"
    main = "ibl",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      indent = {
        -- repeats across the full width of literal TABS
        tab_char = "→",
        -- marks the single start of standard SPACE indents
        char = "→",
      },
      scope = {
        -- disable active context line tracking so all indents look identical
        enabled = false,
      },
    },
  },
}
