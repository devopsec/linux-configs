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
    lazy = false, -- Load on startup
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
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("colorizer").setup()
    end,
  },
}
