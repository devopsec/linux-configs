-- Load polyfills for backward compatibility with older Neovim versions
-- Isolate the environment by removing legacy Vim paths from the runtimepath
require("setup.runtime")

-- Set global and buffer-local Neovim options
require("setup.options")

-- Define custom keybindings and keyboard shortcuts
require("setup.keymaps")
