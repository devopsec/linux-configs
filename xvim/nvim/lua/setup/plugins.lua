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

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
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
    enabled = true,
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
