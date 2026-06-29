-- File Type Detection Order:
-- (1) local ftdetect files (~/.vim/ftdetect/ ~/.config/nvim/ftdetect/)
-- (2) loaded plugins (may override depending on plugin)
-- (3) nvim/vim built-in detection (if filetype not set)
-- (4) shebang detections here (always overwrite on match)
-- (5) filename detections here (ftoverrides did not match, overwrite on match)
-- (6) extension detections here (ftoverrides did not match, overwrite on match)

-- interpreter program -> filetype
local shebang_map = {
  sh        = "sh",
  bash      = "bash",
  dash      = "sh",
  ash       = "sh",
  zsh       = "zsh",
  fish      = "fish",
  ksh       = "ksh",
  ksh93     = "ksh",
  mksh      = "ksh",
  pdksh     = "ksh",
  tcsh      = "tcsh",
  csh       = "tcsh",
  python    = "python",
  python3   = "python",
  ruby      = "ruby",
  perl      = "perl",
  node      = "javascript",
  lua       = "lua",
}

-- file extension -> filetype
local extension_map = {
  fish  = "fish",
  zsh   = "zsh",
  bash  = "bash",
  ksh   = "ksh",
  rasi  = "rasi",
  mdx   = "markdown",
  log   = "log",
}

-- file name / full path -> filetype
local filename_map = {
  [".bashrc"]               = "bash",
  [".bash_profile"]         = "bash",
  [".bash_logout"]          = "bash",
  [".zshrc"]                = "zsh",
  [".zprofile"]             = "zsh",
  [".zshenv"]               = "zsh",
  [".zlogin"]               = "zsh",
  [".zlogout"]              = "zsh",
  [".kshrc"]                = "ksh",
  [".fishrc"]               = "fish",
  ["config.fish"]           = "fish",
  ["Dockerfile"]            = "dockerfile",
  ["docker-compose.yml"]    = "yaml.docker-compose",
  ["docker-compose.yaml"]   = "yaml.docker-compose",
  ["compose.yml"]           = "yaml.docker-compose",
  ["compose.yaml"]          = "yaml.docker-compose",
}

local function extract_shebang_interp(line)
  if not line or not line:match("^#!") then return nil end

  -- Direct interpreter: #!/bin/bash, #!/usr/local/bin/fish
  local direct = line:match("^#!/+.-/([%w._-]+)%s*$")
  if direct and not direct:match("^env$") then
    return direct
  end

  -- env-based shebang: everything after "env"
  local after_env = line:match("^#!.-%senv%s+(.+)$")
  if not after_env then return nil end

  -- Strip env flags before the interpreter:
  --   long flags  : --flag, --flag=val
  --   short flags with values : -u VAR, -C /path
  --   bare short flags : -S, -s
  local rest = after_env
  repeat
    local advanced
    rest, advanced = rest:gsub("^%-%-%S+%s*", "")
    rest, advanced = rest:gsub("^%-[uiC]%s+%S+%s*", "")
    rest, advanced = rest:gsub("^%-[a-zA-Z]%s*", "")
  until advanced == 0

  return rest:match("^([%w._-]+)")
end

local function detect_by_shebang(bufnr)
  local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
  if first_line:find("\0") then return nil end
  local interp = extract_shebang_interp(first_line)
  if not interp then return nil end
  return shebang_map[interp]
end

local function detect_by_filename(bufnr)
  local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  return filename_map[fname]
end

local function detect_by_extension(bufnr)
  local ext = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":e")
  return extension_map[ext]
end

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = vim.api.nvim_create_augroup("ftoverrides", { clear = true }),
  callback = function(args)
    local bufnr = args.buf

    -- skip special buffers (terminal, quickfix, etc.)
    if vim.bo[bufnr].buftype ~= "" then return end

    -- skip unnamed buffers
    if vim.api.nvim_buf_get_name(bufnr) == "" then return end

    -- shebang wins over filename wins over extension
    local ft = detect_by_shebang(bufnr)
              or detect_by_filename(bufnr)
              or detect_by_extension(bufnr)

    if ft then
      vim.bo[bufnr].filetype = ft
    end
  end,
})
