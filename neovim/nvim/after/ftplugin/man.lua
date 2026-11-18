-- A double-click only selects the word; references follow on Ctrl+click
-- (lua/setup/links.lua), not on man.vim's <2-LeftMouse> :Man mapping
pcall(vim.keymap.del, "n", "<2-LeftMouse>", { buffer = true })
