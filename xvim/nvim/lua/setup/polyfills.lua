-- Polyfill for Neovim < 0.10.0 (added joinpath in 0.10.0)
if not vim.fs.joinpath then
    vim.fs.joinpath = function(...)
        return (table.concat({ ... }, "/"):gsub("//+", "/"))
    end
end