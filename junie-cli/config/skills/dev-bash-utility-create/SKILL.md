---
name: dev-bash-utility-create
description: "Implement, extend, or refactor reusable Bash utility functions and shared helpers. Use when creating or refactoring shared Bash libraries, helper functions, or common shell utilities for a project."
---

# Bash Utility Development

## Where Functions Live

Primary location for reusable utility functions:

```
packages/common/utility.sh
```

Sourced into other scripts via:

```bash
source "$REPO_PKGS_DIR/common/utility.sh"
```

Platform-local utilities (not shared across platforms) belong in the relevant platform directory instead.

## Required Standards

All code must comply with `~/.junie/custom/docs/bash/guidelines.md` (or the project's own Bash guideline when present). Full metadata-header spec and script templates: `~/.junie/custom/docs/bash/metadata-header.md`, `~/.junie/custom/docs/bash/script-patterns.md` (load only when needed). Key rules to apply without looking them up:

- **Shebang / shellcheck directive:** Library files use `# shellcheck shell=bash` — no shebang.
- **Library header:** Required immediately after shellcheck directive. Format:
  ```bash
  #
  # SUMMARY:      <one-line description>
  # SRCGUARD:     global
  # VERSION:      <semver>
  #
  ```
- **Source guard:** `utility.sh` uses an `_packages_common_utility_` guard variable — preserve and extend it, do not break it.
- **Strict mode:** Not set in library files; the calling script owns session flags.
- **Variables:** All `local` declarations at the top of the function body, before any logic.
- **Arrays over word lists:** Always use `local -a arr=(...)` for argument lists and collections.
- **Quoting:** All variable expansions must be quoted; unquoted expansions are prohibited.
- **Conditionals:** Use `[[ ]]`, never `[ ]`; always space inside `(( ))`.
- **I/O redirection:** No space between operator and target (`<<<"$var"`, not `<<< "$var"`).
- **Command arrays:** Build commands as arrays (`cmd=(curl --fail); "${cmd[@]}"`).
- **ShellCheck:** All functions must pass `shellcheck` without warnings.
- **Long options preferred:** `grep --recursive` over `grep -r` where readability benefits.

## Workflow

1. **Understand the requirement** — clarify input/output contract, edge cases, performance expectations.
2. **Prototype in `/tmp`** — test the function in isolation before touching `utility.sh`.
   - Organize under `/tmp/<task-slug>/` for clarity.
   - Keep scratch files for review; do not commit or embed them.
3. **Implement in `utility.sh`** — follow the existing code style exactly (blank lines, comment density, function signature style).
4. **Test edge cases** — empty input, stdin vs args, large input, special characters.
5. **Ask before integrating** — if a scratch prototype is good enough to land, confirm with the user before modifying `utility.sh`.

## Efficiency Heuristics

- Avoid subshells for simple string ops; prefer parameter expansion.
- Use `mapfile -t` to read command output into arrays instead of `while read` loops.
- For bulk operations over many items, prefer `xargs --max-procs` or `fd --exec-batch` over sequential shell loops.
- Prefer `printf` over `echo` for formatted output to avoid portability surprises.

## Communication

- Present the implementation and explain any non-obvious choices before writing to the file.
- If performance or correctness trade-offs exist, surface them and let the user decide.
- Do not commit. The user reviews and submits.
