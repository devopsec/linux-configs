-- Load polyfills for backward compatibility with older Neovim versions
-- Isolate the environment by removing legacy Vim paths from the runtimepath
require("setup.runtime")

-- Bootstrap and configure plugins via lazy.nvim
require("setup.plugins")

-- Set global and buffer-local Neovim options
require("setup.options")

-- Define custom keybindings and keyboard shortcuts
require("setup.keymaps")

-- Register autocommands and event-based configurations
require("setup.autocmds")
