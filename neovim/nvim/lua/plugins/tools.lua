return {
  {
    "m00qek/baleia.nvim",
    -- No `cmd`/`event` trigger here on purpose: AnsiOn/AnsiOff/AnsiToggle are
    -- real user commands defined once in lua/setup/autocmds.lua (which also
    -- lazy-loads this plugin itself via require("baleia") on first use).
    -- lazy.nvim's own cmd-based lazy-loading calls nvim_del_user_command()
    -- for every cmd trigger the moment the plugin finishes loading through
    -- *any* path (including a plain require()) -- so declaring `cmd` here
    -- would delete our real commands right after their first successful
    -- invocation, causing a subsequent "E492: Not an editor command" error.
    lazy = true,
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
}
