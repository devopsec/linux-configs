# Junie CLI Specifics for Infra Ollama Server Manage

## Context & Tuning
- Use only `references/ollama.md` and the user config when present; confirm OS, architecture, GPU, model revision, and network boundary before proposing host commands.

## Instructions Overrides
- Never expose the unauthenticated daemon; require approval before model deletion or storage cleanup.

## Performance Notes
- Keep credentials and user prompts out of logs and final summaries; do not commit changes.
