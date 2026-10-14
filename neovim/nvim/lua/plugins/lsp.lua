-- Native Neovim LSP integration (https://neovim.io/doc/user/lsp/), replacing
-- the bloated nvim-lspconfig `setup()` framework + mason.nvim +
-- mason-lspconfig.nvim combo. `nvim-lspconfig` is kept only as a *data
-- source*: it ships one `lsp/<name>.lua` default config file per server,
-- which Neovim 0.11+ discovers on 'runtimepath' the moment `vim.lsp.enable()`
-- is called -- no `require("lspconfig")`/`setup()` call needed at all.
return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("setup.lsp")
    end,
  },
}
