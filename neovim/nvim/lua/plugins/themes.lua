-- Live theme switching (:Themery). The selection is persisted by themery in
-- stdpath("data")/themery/state.json; Catppuccin Coffee (first entry, also
-- the fallback) is the default when nothing has been saved yet.
return {
  { "rebelot/kanagawa.nvim", lazy = true },
  { "ellisonleao/gruvbox.nvim", lazy = true },
  { "nickkadutskyi/jb.nvim", lazy = true },
  { "xiantang/darcula-dark.nvim", lazy = true, dependencies = { "nvim-treesitter/nvim-treesitter" } },
  {
    "zaldih/themery.nvim",
    lazy = false,
    priority = 900,
    cmd = "Themery",
    opts = {
      themes = {
        { name = "Catppuccin Coffee", colorscheme = "catppuccin-mocha" },
        { name = "Kanagawa Wave", colorscheme = "kanagawa-wave" },
        { name = "Kanagawa Dragon", colorscheme = "kanagawa-dragon" },
        { name = "Gruvbox dark", colorscheme = "gruvbox", before = "vim.o.background = 'dark'" },
        { name = "JB", colorscheme = "jb" },
        { name = "Darcula Dark", colorscheme = "darcula-dark" },
      },
      livePreview = true,
    },
  },
}
