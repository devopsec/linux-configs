return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      -- The theme offers four styles: "storm", "moon", "night", and "day"
      style = "night",
      transparent = false, -- Enable this for a transparent background
      terminal_colors = true, -- Configure the colors used when opening a :terminal
      styles = {
        -- Style to be applied to different syntax groups
        comments = { italic = true },
        keywords = { italic = true },
        functions = {},
        variables = {},
      },
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd([[colorscheme tokyonight]])
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
          lualine_z = { 'location' }
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
