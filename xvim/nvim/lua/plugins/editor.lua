-- xvim doesn't use these LazyVim editor defaults today; disabling them avoids
-- their startup/event-hook cost (keymap registration, autocmds, etc.) while
-- keeping the rest of `lazyvim.plugins.editor` (which-key, trouble, gitsigns).
return {
  { "folke/noice.nvim", enabled = false },
  { "akinsho/bufferline.nvim", enabled = false },
  { "nvim-mini/mini.icons", enabled = false },
  { "folke/flash.nvim", enabled = false },
  { "folke/todo-comments.nvim", enabled = false },
  { "MagicDuck/grug-far.nvim", enabled = false },
}
