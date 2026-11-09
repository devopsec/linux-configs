return {
  {
    -- Read Texinfo (`info`) manuals: `:Info [manual]`, `:Info! <word>` (K on a word)
    -- pinned: newer revisions require neovim 0.12 (vim.keymap 'buf' option, health check)
    "ValdezFOmar/info.nvim",
    commit = "ce805c677ed8806712f70535614a5a6fddec855b",
    cmd = "Info",
  },
}
