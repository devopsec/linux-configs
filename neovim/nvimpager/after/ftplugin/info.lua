-- 'q' quits the pager (info.nvim's 'close' fails on the last window)
vim.keymap.set("n", "q", "<Cmd>quit<CR>", { buffer = true, silent = true })

-- <BS> returns to the previously viewed node
vim.keymap.set("n", "<BS>", "<C-o>", { buffer = true, silent = true })
