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
  { import = "plugins" },
}, {
  lockfile = lazysharedir .. "/lazy-lock.json",
  defaults = {
    lazy = true,
  },
  ui = {
    icons = lazy_icons,
  },
})
