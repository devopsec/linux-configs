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
}
