-- Load polyfills for backward compatibility with older Neovim versions
-- Isolate the environment by removing legacy Vim paths from the runtimepath
require("setup.runtime")

-- Bootstrap and configure the pager's lightweight UI plugins
require("setup.plugins")

-- Set global and buffer-local Neovim options
require("setup.options")

-- Define custom keybindings and keyboard shortcuts
require("setup.keymaps")

-- Popup menu (completion, command-line, right-click) key handling
require("setup.menus")

-- Opaque, theme-derived popup/menu/console highlights
require("setup.highlights")
