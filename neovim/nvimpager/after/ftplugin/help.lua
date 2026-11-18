-- A double-click only selects the word (natively the click and its release
-- both jump to the help tag); tags follow on Ctrl+click (lua/setup/links.lua)
vim.keymap.set("n", "<2-LeftMouse>", "<LeftMouse>viw", { buffer = true, silent = true })
vim.keymap.set({ "n", "x" }, "<2-LeftRelease>", "<LeftRelease>", { buffer = true, silent = true })
