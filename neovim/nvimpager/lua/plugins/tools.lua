return {
  {
    -- Read Texinfo (`info`) manuals: `:Info [manual]`, `:Info! <word>` (K on a word)
    -- pinned: newer revisions require neovim 0.12 (vim.keymap 'buf' option, health check)
    "ValdezFOmar/info.nvim",
    commit = "ce805c677ed8806712f70535614a5a6fddec855b",
    cmd = "Info",
  },
  {
    -- <Space> menu of the leader mappings (lua/setup/keymaps.lua), in hydra mode
    -- pinned to the revision lua/setup/whichkey.lua hooks into
    "folke/which-key.nvim",
    commit = "3aab2147e74890957785941f0c1ad87d0a44c15a",
    event = "VeryLazy",
    opts = function()
      return require("setup.whichkey").opts({
        triggers = { { "<leader>", mode = "n" } },
        spec = {
          { "<leader>b", group = "buffer" },
          { "<leader>q", group = "quit" },
          { "<leader>s", group = "search" },
          { "<leader>u", group = "ui" },
          { "<leader>w", group = "windows" },
        },
      })
    end,
    config = function(_, opts)
      require("which-key").setup(opts)
      require("setup.whichkey").patch()
    end,
  },
}
