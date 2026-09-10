-- coq_nvim: manual-only completion (never pops up automatically); navigation
-- keymaps mirroring the old blink.cmp completion_keymap table live in
-- lua/setup/keymaps.lua, guarded by vim.fn.pumvisible().
--
-- NOTE: `auto_start` is a vestigial/inert setting on the current "coq" branch
-- (kept only for forward-compat) -- the actual switch that suppresses every
-- non-manual completion trigger is `completion.skip_after = { "" }`, since
-- every line trivially ends with the empty string, while a manual trigger
-- (<C-F1>) always bypasses that check. `completion.sticky_manual = false`
-- ensures a manual trigger doesn't keep auto-completing on further keystrokes.
--
-- `clients.snippets.enabled = true` keeps coq's own (non 3rd-party) snippet
-- source registered, but it starts toggled OFF via the coq_nvim `config`
-- function below; <C-F2> in lua/setup/keymaps.lua flips it at runtime via
-- `:COQ source on/off snippets`.
vim.g.coq_settings = {
  auto_start = false,
  keymap = {
    recommended = false,
    manual_complete = "<c-f1>",
    jump_to_mark = "",
    pre_select = false,
  },
  completion = {
    skip_after = { "" },
    sticky_manual = false,
  },
  clients = {
    snippets = {
      enabled = true,
    },
  },
}

return {
  {
    "ms-jpq/coq_nvim",
    branch = "coq",
    build = ":COQdeps",
    -- deferred past startup/UIEnter; loading is triggered the moment the user
    -- enters insert mode anywhere, or earlier/explicitly via require("coq")
    -- from setup/lsp.lua so LSP capabilities are still merged correctly
    event = { "InsertEnter" },
    config = function()
      -- start with the (non 3rd-party) snippet completion source disabled;
      -- <C-F2> toggles it on/off at runtime (see lua/setup/keymaps.lua)
      local ok, toggle = pcall(require, "coq.lib.producers.toggle")
      if ok then
        toggle.set("snippets", false)
      end
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    commit = vim.fn.has("nvim-0.12") == 0 and "7caec274fd19c12b55902a5b795100d21531391f" or nil,
    version = false, -- last release is way too old and doesn't work on Windows
    build = function()
      local TS = require("nvim-treesitter")
      if not TS.get_installed then
        LazyVim.error("Please restart Neovim and run `:TSUpdate` to use the `nvim-treesitter` **main** branch.")
        return
      end
      -- make sure we're using the latest treesitter util
      package.loaded["lazyvim.util.treesitter"] = nil
      LazyVim.treesitter.build(function()
        TS.update(nil, { summary = true })
      end)
    end,
    event = { "LazyFile", "VeryLazy" },
    cmd = { "TSUpdate", "TSInstall", "TSLog", "TSUninstall" },
    opts_extend = { "ensure_installed" },
    -- @alias lazyvim.TSFeat { enable?: boolean, disable?: string[] }
    -- @class lazyvim.TSConfig: TSConfig
    opts = {
      -- LazyVim config for treesitter
      indent = { enable = true }, ---@type lazyvim.TSFeat
      highlight = { enable = true }, ---@type lazyvim.TSFeat
      folds = { enable = true }, ---@type lazyvim.TSFeat
      ensure_installed = {
        "asm",
        "awk",
        "bash",
        "c",
        "c3",
        "cmake",
        "cpp",
        "css",
        "csv",
        "desktop",
        "diff",
        "dockerfile",
        "ebnf",
        "editorconfig",
        "git_config",
        "gitattributes",
        "gitignore",
        "go",
        "hcl",
        "html",
        "ini",
        "java",
        "javascript",
        "jinja",
        "jinja_inline",
        "jq",
        "jsdoc",
        "json",
        "json5",
        "lua",
        "luadoc",
        "luap",
        "markdown",
        "markdown_inline",
        "nasm",
        "nginx",
        "perl",
        "php",
        "phpdoc",
        "powershell",
        "printf",
        "properties",
        "python",
        "query",
        "regex",
        "ruby",
        "rust",
        "sql",
        "toml",
        "twig",
        "vim",
        "vimdoc",
        "xml",
        "yaml",
      },
    },
    -- @param opts lazyvim.TSConfig
    config = function(_, opts)
      local TS = require("nvim-treesitter")

      setmetatable(require("nvim-treesitter.install"), {
        __newindex = function(_, k)
          if k == "compilers" then
            vim.schedule(function()
              LazyVim.error({
                "Setting custom compilers for `nvim-treesitter` is no longer supported.",
                "",
                "For more info, see:",
                "- [compilers](https://docs.rs/cc/latest/cc/#compile-time-requirements)",
              })
            end)
          end
        end,
      })

      -- some quick sanity checks
      if not TS.get_installed then
        return LazyVim.error("Please use `:Lazy` and update `nvim-treesitter`")
      elseif type(opts.ensure_installed) ~= "table" then
        return LazyVim.error("`nvim-treesitter` opts.ensure_installed must be a table")
      end

      -- setup treesitter
      TS.setup(opts)
      LazyVim.treesitter.get_installed(true) -- initialize the installed langs

      -- install missing parsers
      local install = vim.tbl_filter(function(lang)
        return not LazyVim.treesitter.have(lang)
      end, opts.ensure_installed or {})
      if #install > 0 then
        LazyVim.treesitter.build(function()
          TS.install(install, { summary = true }):await(function()
            LazyVim.treesitter.get_installed(true) -- refresh the installed langs
          end)
        end)
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("lazyvim_treesitter", { clear = true }),
        callback = function(ev)
          local ft, lang = ev.match, vim.treesitter.language.get_lang(ev.match)
          if not LazyVim.treesitter.have(ft) then
            return
          end

          -- @param feat string
          -- @param query string
          local function enabled(feat, query)
            local f = opts[feat] or {} ---@type lazyvim.TSFeat
            return f.enable ~= false
              and not (type(f.disable) == "table" and vim.tbl_contains(f.disable, lang))
              and LazyVim.treesitter.have(ft, query)
          end

          -- highlighting
          if enabled("highlight", "highlights") then
            pcall(vim.treesitter.start, ev.buf)
          end

          -- indents
          if enabled("indent", "indents") then
            LazyVim.set_default("indentexpr", "v:lua.LazyVim.treesitter.indentexpr()")
          end

          -- folds
          if enabled("folds", "folds") then
            if LazyVim.set_default("foldmethod", "expr") then
              LazyVim.set_default("foldexpr", "v:lua.LazyVim.treesitter.foldexpr()")
            end
          end
        end,
      })
    end,
  }
}
