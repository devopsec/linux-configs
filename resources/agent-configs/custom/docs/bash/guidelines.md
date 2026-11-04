# Bash Guidelines

Rules only. Full templates and the metadata-header spec live next to this file (`metadata-header.md`, `script-patterns.md`); load them only when authoring a package header or a new script skeleton.

## File header
- Executables: first line `#!/usr/bin/env bash` (never a fixed path). Sourced/library files: no shebang, `# shellcheck shell=bash` instead.
- Metadata comment block (`# PACKAGE:` / `# VERSION:` / `# SUMMARY:` + optional `SRCGUARD`, `VARPREFIX`, `FNPREFIX`, `LICENSE`) is required only for top-level package entrypoints (`packages/`); otherwise omit unless asked. It follows the shebang/directive immediately. Spec: `metadata-header.md`.
- `usage()` directly after the header; every script supports `-h`. Libraries need no `usage()`.

## Session setup
- Strict mode by default: `set -Eeuo pipefail; shopt -s inherit_errexit nullglob` (under `bashdb`, i.e. `_Dbg_set_debug` set, drop `-e`). `DEBUG=1` → `set -x`. Libraries do not set flags; the caller owns them.
- Resolve repo paths from `${BASH_SOURCE[0]}` (`realpath -m`), then `source` shared libs with `# shellcheck source=` hints; install `trap_push 'backtrace "$LINENO"' ERR` outside the debugger.
- Scripts end with `main() { … }` + `main "$@"`.

## Variables & expansion
- Declare all variables at the top of their scope (function body, subshell, or after the header); `local` inside functions (`local -a` for arrays); `export` only with a reason.
- Quote every expansion: `"$var"`, `"${arr[@]}"`, `"$@"`. Unquoted only when explicitly required.
- Arrays, never space-separated word lists, when argument boundaries matter; build commands as arrays (`cmd=(curl --fail); cmd+=(--header "$h"); "${cmd[@]}"`).
- Safe expansion for config: `${VAR:-default}`, `${VAR:=default}`, `: "${API_KEY:?missing API_KEY}"`.
- Split command output with `mapfile -t` / `read`, not word-splitting command substitution (SC2207).

## Syntax
- `[[ … ]]`, never `[ … ]`; keep spaces inside `(( DEBUG == 1 ))`.
- No space between redirection operator and target: `<<<"$var"`, `>"$f"`; spaces are fine around pipes/process substitution.
- Prefer long options (`--recursive`) for readability; short forms acceptable.
- Default to Bash; POSIX `sh` only with a documented portability reason.

## Robustness
- Validate dependencies before use: `command -v rsync &>/dev/null || { echo 'missing dependency: rsync' >&2; exit 1; }`; document required packages.
- Never trust CLI args, env, command output or filesystem state: check `$#`, use `case` allowlists (`dev|stage|prod`).
- stdout = program output, stderr = diagnostics (`log()` → `>&2`, ISO timestamps).
- Clean up temp resources via `trap … EXIT` (declared before the resource is created, with `|| true` to avoid double handling); avoid traps that reference variables/functions that can go out of scope. Applies to build dirs, tempfiles, lock files, background jobs. Signal details: `/documentation/user/bash-sig-handling.md`.
- Concurrency (cron/CI/timers): atomic `mkdir "$LOCKDIR"` lock.
- All scripts pass `shellcheck`; CI enforces it.

## Scope
- Bash for orchestration, filesystem automation, env validation, service wrappers, pipeline glue.
- Not for complex parsing, floating-point math, large application logic or stateful workflows — escalate to Python or Go.
