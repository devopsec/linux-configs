# Claude Specifics for Infra Ollama Server Manage

## Context & Tuning
- Load only `references/ollama.md` and follow the configured bind/model-store defaults; prefer verified release assets and immutable images.

## Instructions Overrides
- Never suggest a public unauthenticated listener; ask before destructive model-store changes.

## Performance Notes
- Redact credentials/customer prompts and validate health plus one representative inference without printing sensitive content.
