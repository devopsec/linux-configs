# Custom slash commands

Junie CLI supports custom slash commands that you can create to quickly execute frequently used prompts or
repetitive tasks. Custom commands are added to the list of built-in slash commands that is shown when you type `/`.

[//]: # (![]&#40;custom-slash-command.png&#41;{width="706"})

To create a custom command:

1. Use `/commands` → `Create New Command` and provide the command name and description.

2. Select the command scope:
    * *Project-specific commands* are stored as Markdown files in the `.junie/commands` folder at your project’s root directory.
      You can commit this folder to version control to ensure that all team members can use it.
    * *User commands* are stored as Markdown files in the `~/.junie/commands` folder on your machine, making them
      available across all projects you open locally.

3. Enter and save the prompt.

To view, modify, or delete the added custom commands in interactive mode, use `/commands`.

In ACP clients, `/commands` lists the custom commands available in the session (name, description, source, arguments) and explains how to run them with `/name`. Create and edit still happen by editing the Markdown files above or by using the TUI `/commands` screen.

### Use arguments in the command prompt

You can use special keywords with a dollar-sign prefix and an argument name in the prompt text to pass parameter values when invoking
the custom slash command.

For example, if you create a command named *explain* and set the prompt as `Explain the code in` plus a `file` template arg,  
the `/explain` slash command should be used with the `file` argument when invoked as follows:

```
/explain file=src/main.kt
```

Argument values may be either unquoted or quoted with double or single quotes.

> A custom slash command will only be executed when all **named** arguments from the command template are provided.
>
> Junie CLI shows inline hints for missing arguments. To autocomplete the missing argument name, use `Tab`.

By default, custom slash commands accept only the named arguments defined in the command template. Commands created
through the `/commands` wizard use this default.

### Optional free-form text (`allowPromptArgument`)

To also accept free-form text the way some built-in slash commands do,
add `allowPromptArgument: true` to the command's YAML frontmatter. This exposes an additional **`$prompt`** argument:
you can reference **`$prompt`** explicitly in the prompt text, or, if you don't, any free text passed when invoking the
command is appended automatically as `User Input: ...`.

Use this for CLI-style wrappers (for example `/histmgr list --limit 10`) so that:

- bare `/histmgr` runs immediately (with a documented default), and
- trailing text is optional — **not** a required `ARGUMENTS=` Tab completion.

**Fast path for script wrappers:** keep the body to one bash line and put `$prompt` unquoted after the script so Junie
substitutes argv directly (e.g. `python3 ~/.junie/custom/scripts/agentmgr/agentmgr.py $prompt`). Do **not** put other
dollar vars (including `$HOME`) in the body — they become required named args. Prefer `~/...` paths. Scripts should
default when argv is empty. For zero-LLM latency, also install `~/.junie/custom/bin/<name>` shims on `PATH` (see `commands-catalog.md`).

**Anti-pattern:** a single catch-all `ARGUMENTS` dollar-placeholder in the body. Junie treats that as a **required**
named arg, so bare `/cmd` does nothing and Tab shows `ARGUMENTS=`. Prefer `allowPromptArgument: true` + `$prompt`.

**Anti-pattern:** long agent manuals as the command body. The agent re-interprets them slowly; thin EXECUTE + script is faster.

### Slash command file format

Each custom slash command is saved as a separate Markdown file with YAML frontmatter that defines the command metadata.
The file name is taken from the command name.

Example with a **required** named arg:

```markdown
---
description: Explains code in a given file
---

Explain the code in the path given as the file argument and suggest improvements.
```

(Use a dollar-sign + `file` placeholder in the body only when `file=...` must be supplied.)

Example with **optional** free-form CLI text (global tools under `~/.junie/commands/`):

```markdown
---
description: Manage Junie session history
allowPromptArgument: true
---

Run the history manager. If there is no user input, default to mine --limit 20.
If user input is present, treat it as CLI args or map natural language to a subcommand.
```

### Session PATH for command shims

Zero-LLM shims in `~/.junie/custom/bin` are on PATH for Junie sessions via a scoped `junie()` wrapper in `~/.profile` (prepend only for the junie process tree). See `commands-catalog.md`.
