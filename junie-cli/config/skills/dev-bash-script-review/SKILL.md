---
name: "dev-bash-script-review"
description: "Review, audit, or assess a Bash script or shell function in this project. Use when asked to check for correctness, edge cases, exit code propagation, signal handling, security, or performance — including phrases like \"review this\", \"audit this\", or \"what do you think about this\" applied to shell code."
---

# Bash Code Review

## Review Process

**Present findings first. Do not modify files until the user approves.**

This is a hard rule — surface all issues in a structured report, discuss, then implement only what is agreed upon.

## Review Checklist

Work through these categories in order. Report all findings, not just blockers.

### 1. Correctness

- Exit codes propagated correctly through pipelines and subshells (`set -Eeuo pipefail`, `inherit_errexit`)
- `ERR` trap and `EXIT` trap present and correct where expected
- No partial execution risk (script uses `main()` entrypoint)
- Conditionals use `[[ ]]`, never `[ ]`
- Arithmetic uses `(( ))` with spaces inside
- No unquoted variable expansions (word-splitting / glob risk)
- Arrays used where argument boundaries must be preserved

### 2. Signal & Trap Handling

- `trap_push` used (not bare `trap`) when stacking signal handlers
- Cleanup traps use `|| true` failsafe to avoid re-entrancy issues
- Trap references (function names / variables) remain in scope when the trap fires
- Temporary resources (dirs, files, locks, background jobs) cleaned up on `EXIT`
- See `documentation/user/bash-sig-handling.md` for project-specific patterns

### 3. Edge Cases & Input Validation

- CLI arguments validated before use; out-of-range or missing args handled explicitly
- Allowlists used where input domain is finite (e.g., `case "$env" in dev|prod) ;;`)
- External command output never trusted without validation
- Empty input / zero-length arrays handled without silent failure
- Filesystem state not assumed (files may not exist, dirs may lack permissions)

### 4. Error Handling & Logging

- Errors go to stderr (`>&2`), not stdout
- No swallowed errors (`|| true` used only where intentional and commented)
- Dependency presence validated before use (`command -v foo || { ... exit 1; }`)
- Log messages have timestamps and context (see `log()` pattern in `~/.junie/custom/docs/bash/guidelines.md`)

### 5. Efficiency

- No unnecessary subshells for string ops (use parameter expansion instead)
- `mapfile -t` used to read command output into arrays (avoids SC2207 word-splitting)
- Bulk operations use `xargs --max-procs` or `fd --exec-batch` rather than sequential loops
- Command arrays built as arrays, not string concatenation

### 6. Style & Maintainability

- Variables declared with `local` at the top of function scope — no mid-function declarations
- Shebang / shellcheck directive correct for file type (library: `# shellcheck shell=bash`, no shebang)
- Library header present and accurate (SUMMARY, SRCGUARD, VERSION)
- Source guard present in library files and not broken
- Long options preferred for readability (`grep --recursive` over `grep -r`)
- No space between redirection operator and target (`<<<"$var"`)
- Passes `shellcheck` without warnings

### 7. Security

- No credentials, tokens, or secrets in plaintext or interpolated into commands
- External inputs sanitized before use in commands or filenames
- Temporary files created with `mktemp`, not predictable paths

## Reporting Format

Group findings by category. For each issue:

- **Severity:** `critical` / `warning` / `suggestion`
- **Location:** function name or line range
- **Issue:** one-sentence description
- **Recommendation:** what to change and why

After the report, summarize: what's solid, what must change, what's optional.

## After Review

- Wait for user to approve which findings to act on.
- Implement only approved changes.
- Re-run `shellcheck` after changes.
- Do not commit. The user reviews and submits.
