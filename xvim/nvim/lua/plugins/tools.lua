return {
  {
    "m00qek/baleia.nvim",
    cmd = { "AnsiOn", "AnsiOff", "AnsiToggle" },
  },
  {
    "LunarVim/bigfile.nvim",
    event = { "BufReadPre" },
    config = function()
      require("bigfile").setup({
        filesize = 1,
        pattern = { "*" },
        features = { "indent_blankline", "illuminate", "lsp", "treesitter", "syntax", "matchparen", "vimopts", "filetype" },
      })
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.5",
    cmd = "Telescope",
    keys = {
      { "<C-f>", "<cmd>Telescope find_files<cr>" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>" },
    },
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local actions = require("telescope.actions")
      require("telescope").setup({
        defaults = {
          mappings = {
            i = {
              ["<Esc>"] = actions.close,
            },
            n = {
              ["q"] = actions.close,
              ["<Esc>"] = actions.close,
            },
          },
        },
      })
    end,
  },
}
