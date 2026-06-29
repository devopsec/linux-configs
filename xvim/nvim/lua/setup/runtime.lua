vim = vim or {}

-- Polyfill for Neovim < 0.10.0 (added joinpath in 0.10.0)
if not vim.fs.joinpath then
    vim.fs.joinpath = function(...)
        return (table.concat({ ... }, "/"):gsub("//+", "/"))
    end
end

-- Remove vim paths from runtimepath - only use neovim configs
vim.opt.runtimepath:remove(vim.fn.expand("~/.vim"))
vim.opt.runtimepath:remove(vim.fn.expand("~/.vim/after"))

-- Set leader and local leader (required before changing any settings)
vim.g.mapleader = " "
vim.g.maplocalleader = " "
