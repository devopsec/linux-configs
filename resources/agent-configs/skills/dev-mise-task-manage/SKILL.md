---
name: dev-mise-task-manage
description: Create, update, run, debug, discover, or show help for mise tasks (file tasks and TOML tasks), including task interfaces, usage directives, and output behavior. Use when a request mentions a mise task, `mise run`, `mise.toml` tasks, or a tasks directory.
model: haiku
---

# Mise Task Management

Complements any general script-authoring skill; prefer the rules here for task-runner specifics and defer to general script rules for script structure.

## Workflow

1. **Discover** - `mise tasks` (alias `mise tasks ls`), `mise tasks info <task>`, `mise run <task> --help`.
2. **Detect conventions** - existing task style (file vs TOML), tasks directory, script language.
3. **Author or edit** - follow the guidelines below.
4. **Verify** - `mise run <task> --help`, then run the task.

## Execution

- Run tasks with `mise run <task>`.
- Use `mise tasks info <task>` to tell repository tasks from user-global tasks.

## Authoring

Match the style the project already uses; do not introduce a second style without clear reason.

### Script language

- Detect the language from existing task files and scripts. If mixed or unclear, default to Bash for simple tasks.
- Move to a better-fit language when Bash becomes hard to maintain; if scripts are standardized on one language, keep it.

### File tasks ([docs](https://mise.jdx.dev/tasks/file-tasks.html))

- Place in the configured tasks directory (see docs for defaults and `task_config.includes`); make the file executable.
- Use an extension matching the language (`.sh`, `.zsh`, `.js`, `.ts`).
- Treat task files as task-runner entry points; no direct-execution compatibility unless requested.
- Keep files named `_default` extensionless, or default-task resolution breaks.
- Put shared/reusable code outside directories mise scans for tasks, or it becomes a task entry.

### TOML tasks ([docs](https://mise.jdx.dev/tasks/toml-tasks.html))

- One `[tasks.<name>]` table per task in `mise.toml` or `.mise.toml`.
- Set metadata (`description`, `depends`, `env`, `sources`, `outputs`, `dir`, `usage`, `quiet`) per [task configuration](https://mise.jdx.dev/tasks/task-configuration.html).

## Usage and Help

- Let [usage](https://usage.jdx.dev/) own the task interface (args, options, defaults, validation, help). Do not reimplement argument parsing or help printing in scripts.
- Directives by language: `#USAGE` (shell), `//USAGE` (TypeScript), `usage` field (TOML). See the [arguments docs](https://mise.jdx.dev/tasks/file-tasks.html#arguments).
- Basic Markdown (`**bold**`, backticks) is allowed in `#MISE description`, `help`, `long_help`.
- Treat unknown or incomplete options as explicit errors.

## Output

- Default tasks to quiet so output has no `[task-name]` prefix: `quiet = true` (TOML) or `#MISE quiet=true` (file tasks, or the language's directive syntax).
