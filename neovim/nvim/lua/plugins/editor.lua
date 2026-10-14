-- This config doesn't use these LazyVim editor defaults today; disabling them avoids
-- their startup/event-hook cost (keymap registration, autocmds, etc.) while
-- keeping the rest of `lazyvim.plugins.editor` (which-key, trouble, gitsigns).
return {
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.triggers = {
        { "<auto>", mode = { "n", "i", "o", "t", "c" } },
      }
      opts.plugins = opts.plugins or {}
      opts.plugins.presets = vim.tbl_deep_extend("force", opts.plugins.presets or {}, {
        operators = false,
        motions = false,
        text_objects = false,
      })
      return opts
    end,
  },
  { "akinsho/bufferline.nvim", enabled = false },
  { "nvim-mini/mini.icons", enabled = false },
  { "folke/flash.nvim", enabled = false },
  { "folke/todo-comments.nvim", enabled = false },
  { "MagicDuck/grug-far.nvim", enabled = false },
}
