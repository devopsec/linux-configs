-- Native Neovim LSP integration (https://neovim.io/doc/user/lsp/).
-- Replaces nvim-lspconfig's `setup()` framework + mason.nvim +
-- mason-lspconfig.nvim: nvim-lspconfig is only used as a passive source of
-- default `lsp/<name>.lua` server configs (cmd/filetypes/root_markers),
-- discovered automatically on 'runtimepath' by vim.lsp.enable()/vim.lsp.config().

-- coq_nvim must be loaded *before* building server configs so its LSP
-- capabilities (snippet support, etc.) are merged in before the client
-- attaches -- see https://github.com/ms-jpq/coq_nvim#lsp. It's only
-- require()'d (lazy-loading it) below, and only if at least one server is
-- actually going to be enabled -- e.g. a shell script buffer with no LSP
-- server installed never pulls coq_nvim in via this path at all.
---@param opts vim.lsp.Config
---@return vim.lsp.Config
local function with_coq(opts)
  local ok, coq = pcall(require, "coq")
  if ok then
    return coq.lsp_ensure_capabilities(opts)
  end
  return opts
end

-- =================================================================================
-- Diagnostics
-- =================================================================================

local diagnostic_icons = (LazyVim and LazyVim.config and LazyVim.config.icons.diagnostics) or {
  Error = "E",
  Warn = "W",
  Info = "I",
  Hint = "H",
}

vim.diagnostic.config({
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  virtual_text = {
    spacing = 4,
    source = "if_many",
    prefix = "●",
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = diagnostic_icons.Error,
      [vim.diagnostic.severity.WARN] = diagnostic_icons.Warn,
      [vim.diagnostic.severity.HINT] = diagnostic_icons.Hint,
      [vim.diagnostic.severity.INFO] = diagnostic_icons.Info,
    },
  },
})

-- =================================================================================
-- Keymaps (buffer-local, set on LspAttach)
-- =================================================================================

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("NativeLspKeymaps", { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    local bufopts = { buffer = ev.buf, silent = true }

    local function map(mode, lhs, rhs, has, desc)
      if has and client and not client:supports_method(has) then
        return
      end
      vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", bufopts, { desc = desc }))
    end

    -- keymaps are only set when an LSP can handle the filetype
    map("n", "gd", vim.lsp.buf.definition, "textDocument/definition", "Goto Definition")
    map("n", "gD", vim.lsp.buf.declaration, "textDocument/declaration", "Goto Declaration")
    map("n", "gI", vim.lsp.buf.implementation, "textDocument/implementation", "Goto Implementation")
    map("n", "gy", vim.lsp.buf.type_definition, "textDocument/typeDefinition", "Goto Type Definition")
    map("n", "gr", vim.lsp.buf.references, "textDocument/references", "References")
    map("n", "K", vim.lsp.buf.hover, "textDocument/hover", "Hover")
    map("n", "gK", vim.lsp.buf.signature_help, "textDocument/signatureHelp", "Signature Help")
    map("i", "<C-k>", vim.lsp.buf.signature_help, "textDocument/signatureHelp", "Signature Help")
    map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, "textDocument/codeAction", "Code Action")
    map("n", "<leader>cr", vim.lsp.buf.rename, "textDocument/rename", "Rename")
    map("n", "<leader>cl", vim.cmd.LspInfo, nil, "Lsp Info")

    -- =============================================================================
    -- ULTRA-FAST TARGETED FORMATTING (F4)
    -- =============================================================================
    map("n", "<F4>", function()
      -- Bypass the generic global formatter loop. 
      -- Call the exact client attached to this specific execution context directly.
      client.request("textDocument/formatting", {
        textDocument = vim.lsp.util.make_text_document_params(ev.buf),
        options = vim.lsp.util.make_formatting_params().options,
      }, function(err, result, ctx)
        if err then
          vim.notify("Formatting failed: " .. err.message, vim.log.levels.ERROR, { title = client.name })
          return
        end
        if result then
          -- Safely apply changes smoothly to the buffer
          vim.lsp.util.apply_text_edits(result, ev.buf, client.offset_encoding)
          vim.notify("Formatted via " .. client.name, vim.log.levels.INFO, { title = "Native LSP", icon = "✨" })
        end
      end, ev.buf)
    end, "textDocument/formatting", "Format Buffer (Targeted)")

  end,
})

-- =================================================================================
-- Servers
-- =================================================================================
-- Minimal, hand-picked set covering the languages xvim's own nvim-treesitter
-- `ensure_installed` list already targets. Each is only enabled if its binary
-- is actually found on $PATH -- no auto-installer (mason) is involved, so
-- missing servers are silently skipped instead of erroring.

---@type table<string, string>
local servers = {
  lua_ls = "lua-language-server",
  pyright = "pyright-langserver",
  bashls = "bash-language-server",
  clangd = "clangd",
  gopls = "gopls",
  rust_analyzer = "rust-analyzer",
}

for name, cmd in pairs(servers) do
  if vim.fn.executable(cmd) == 1 then
    vim.lsp.config(name, with_coq({}))
    vim.lsp.enable(name)
  end
end

