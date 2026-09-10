-- typically ~/.local/share/nvim/lazy
local lazysharedir  = vim.fn.stdpath("data") .. "/lazy"
local lazyrepodir   = lazysharedir .. "/lazy.nvim"
local lazyrepourl   = "https://github.com/folke/lazy.nvim.git"

-- Bootstrap lazy.nvim
if not (vim.uv or vim.loop).fs_stat(lazyrepodir) then
  local out = vim.fn.system({
      "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepourl, lazyrepodir
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazyrepodir)

-- Configure lazy.nvim
local lazy_icons = nil

if not vim.g.have_nerd_font then
  lazy_icons = {
    cmd = ">",
    config = "C",
    event = "E",
    ft = "F",
    init = "I",
    import = "M",
    keys = "K",
    lazy = "L",
    loaded = "+",
    not_loaded = "-",
    plugin = "P",
    runtime = "R",
    require = "Q",
    source = "S",
    start = "*",
    task = "T",
    list = {
      "-",
      "*",
      "+",
      ">",
    },
  }
end

-- LazyVim's own startup import-order check (lazyvim/config/init.lua) looks
-- for a module literally named "lazyvim.plugins" (the full wildcard) as the
-- very first import; since we intentionally import only curated submodules
-- (lazyvim.plugins.init/.coding/.editor) instead of that wildcard -- for
-- performance, see lua/plugins/lsp.lua/syntax.lua -- that check would always
-- (falsely) warn "import order is incorrect" no matter how these are
-- ordered, so it's disabled here.
vim.g.lazyvim_check_order = false

-- TODO:  implement a better solution for plugin updates that integrates with existing pkg/app mgrs.

require("lazy").setup({
  spec = {
    -- add LazyVim, but only import the specific modules xvim actually
    -- benefits from instead of the full "lazyvim.plugins" wildcard (which
    -- also pulls in nvim-lspconfig/mason/mason-lspconfig, and auto-enables
    -- default LazyVim "extras" such as the blink.cmp completion extra --
    -- none of which are wanted now that LSP is native and coq_nvim is used).
    -- Import order below still follows LazyVim's convention (its own
    -- modules first, then any lazyvim.plugins.extras.*, then our own
    -- "plugins") for consistency, even though the order-check above can't
    -- validate it given the non-wildcard import.
    { "LazyVim/LazyVim", import = "lazyvim.plugins.init" },
    { import = "lazyvim.plugins.coding" },
    { import = "lazyvim.plugins.editor" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  lockfile = lazysharedir .. "/lazy-lock.json",
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = true,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  ui = {
    icons = lazy_icons,
  },
  checker = {
    -- check for plugin updates periodically
    enabled = false,
    -- notify on update
    notify = true,
  },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
