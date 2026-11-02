#!/usr/bin/env bash
#
# No-UI headless startup smoke test for the neovim family (nvim, nvimgit, nvimpager).
# Each case loads its config headlessly, captures output, and asserts both a zero
# exit code and the absence of known error-pattern lines; failures are reported
# per-app instead of only an aggregate exit code. Runs with no vim present.

set -uo pipefail

function usage() {
cat <<EOF
Usage:          $0 [app]
  all apps:     $0
  one app:      $0 nvimgit
EOF
}

if (( $# > 1 )); then
    usage
    exit 1
fi

# known error signatures from real bug reports (vim/nvim errors, module load
# failures, nil-value Lua crashes) -- a clean config load must contain none
declare -gr ERROR_PATTERN='E[0-9]+:|^Error |module .* not found|attempt to call field'

declare -gi OVERALL_RESULT=0

# runs a headless command, captures combined output, and asserts exit code 0
# plus no ERROR_PATTERN match; prints PASS/FAIL and updates OVERALL_RESULT
function assert_clean_run() {
    local name="$1"
    shift
    local output rc

    echo '==============================='
    echo "Testing $name"
    echo '==============================='

    output="$("$@" 2>&1)"
    rc=$?
    echo "$output"
    echo ''

    if (( rc != 0 )); then
        echo "FAIL: $name exited with status $rc"
        OVERALL_RESULT=1
        return 1
    fi

    if grep -qE "$ERROR_PATTERN" <<< "$output"; then
        echo "FAIL: $name produced an error-pattern match in its output"
        OVERALL_RESULT=1
        return 1
    fi

    echo "PASS: $name"
    return 0
}

function test_nvim_app() {
    local nvim_app="$1"
    NVIM_APPNAME="$nvim_app" assert_clean_run "$nvim_app" nvim --headless --startuptime /dev/stdout -c 'qall!'
    test_behavior "$nvim_app"
}

# asserts options, key mappings and popup highlights of a loaded config (headless Lua)
function test_behavior() {
    local nvim_app="$1"
    local lua
    lua=$(cat <<'LUA'
local missing = {}
local function need(cond, what) if not cond then missing[#missing + 1] = what end end
local function mapped(mode, lhs) return vim.fn.maparg(lhs, mode) ~= "" end
local function hl(n) return vim.api.nvim_get_hl(0, { name = n, link = false }) end
vim.defer_fn(function()
  need(vim.o.mouse == "a", "mouse=a")
  need(vim.o.pumblend == 0 and vim.o.winblend == 0, "pumblend/winblend=0")
  need(vim.o.guifont:find("JetBrains", 1, true), "guifont")
  need(vim.g.colors_name ~= nil, "colorscheme")
  for _, lhs in ipairs({ "<C-PageUp>", "<C-PageDown>", "<C-Home>", "<C-End>", "<C-A-PageUp>", "<C-A-PageDown>",
      "<C-A-Home>", "<C-A-End>", "<C-A-Up>", "<C-A-Down>", "<C-A-Left>", "<C-A-Right>" }) do
    need(mapped("n", lhs), "n " .. lhs)
  end
  for _, lhs in ipairs({ "<Home>", "<End>", "<PageUp>", "<PageDown>", "<Tab>", "<S-Tab>", "<CR>", "<LeftMouse>" }) do
    need(mapped("i", lhs), "i " .. lhs)
  end
  for _, lhs in ipairs({ "<Up>", "<Down>", "<Left>", "<Right>", "<Home>", "<End>", "<Tab>", "<S-Tab>", "<CR>", "<LeftMouse>" }) do
    need(mapped("c", lhs), "c " .. lhs)
  end
  for _, lhs in ipairs({ "<ScrollWheelUp>", "<ScrollWheelDown>" }) do
    need(mapped("i", lhs), "i " .. lhs)
  end
  need(hl("Pmenu").bg and hl("Pmenu").bg ~= hl("Normal").bg or hl("Normal").bg == nil, "Pmenu distinct from Normal")
  need(hl("NoiceConsoleBorder").fg ~= hl("NoiceCmdlinePopupBorder").fg, "console border differs from cmdline border")
  if vim.env.NVIM_APPNAME == "nvim" then
    need(vim.fn.exists(":Themery") == 2, ":Themery")
  end
  if #missing > 0 then
    io.stderr:write("BEHAVIOR MISSING: " .. table.concat(missing, ", ") .. "\n")
    vim.cmd("cquit 1")
  end
  vim.cmd("qa!")
end, 1500)
LUA
)
    NVIM_APPNAME="$nvim_app" assert_clean_run "${nvim_app}_behavior" nvim --headless -c "lua $lua"
}

# resolves a guaranteed-unsandboxed nvim for the runtime-load test below:
# a native system nvim, else whatever 'nvim' is on PATH (which may be the
# Flatpak-sandboxed one and unable to see $runtime, by design the exact bug
# this test exists to catch)
function resolve_unsandboxed_nvim() {
    local candidate
    for candidate in /usr/bin/nvim /bin/nvim; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    command -v nvim
}

# reproduces nvimpager's own stage1/stage2 runtime-load sequence (extracted
# from the real '/usr/bin/nvimpager' script) directly against $RUNTIME,
# bypassing the 'nvimpager' command itself (which short-circuits to a plain
# 'cat' passthrough on a non-tty stdout, so it never exercises this path)
function test_nvimpager_runtime_load() {
    local runtime='/usr/share/nvimpager/runtime'
    local nvim_bin

    if [[ ! -d "$runtime" ]]; then
        echo '==============================='
        echo 'Testing nvimpager_runtime_load'
        echo '==============================='
        echo "SKIP: nvimpager runtime not found at '$runtime'"
        echo ''
        return 0
    fi

    nvim_bin="$(resolve_unsandboxed_nvim)"

    RUNTIME="$runtime" NVIM_APPNAME=nvimpager assert_clean_run nvimpager_runtime_load \
        "$nvim_bin" --headless \
        --cmd "set rtp+=$runtime" \
        -c 'lua nvimpager = require("nvimpager")' \
        -c 'lua nvimpager.stage1()' \
        -c 'lua nvimpager.stage2()' \
        -c 'qa!'
}

if (( $# == 1 )); then
    case "$1" in
    nvim | nvimgit | nvimpager) test_nvim_app "$1" ;;
    nvimpager_runtime_load) test_nvimpager_runtime_load ;;
    *)
        usage
        exit 1
        ;;
    esac
    exit "$OVERALL_RESULT"
fi

for nvim_app in nvim nvimgit nvimpager; do
    test_nvim_app "$nvim_app"
done
test_nvimpager_runtime_load

exit "$OVERALL_RESULT"
