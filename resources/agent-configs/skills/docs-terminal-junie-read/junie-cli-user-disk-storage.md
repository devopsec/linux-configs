# Junie CLI: What is stored on the user's disk

This document describes what data the `junie` CLI stores on the user's disk, where it is stored, and what it is used for.

## Base `junieHome` directory

The main user directory for the CLI is `junieHome`.

The path is resolved in this order:

1. the `JUNIE_HOME` environment variable
2. the `junie.home` system property
3. the default directory `~/.junie`

Examples:

- macOS / Linux: `~/.junie`
- Windows: `%USERPROFILE%/.junie`

## What is stored inside `junieHome`

### `logs/`

Directory for CLI logs. It is created when the application starts.

### `settings.json`

File with CLI user settings.

At the moment, it stores values such as:

- `braveMode`
- `modelForLaunch`
- `selectedTheme`
- `sessionCount`
- `junieId`
- `shareAnonymousStatistics`

Format: JSON.

### `sessions/`

Directory with saved CLI sessions.

Structure:

- `sessions/index.jsonl` — session index, one JSON record per line
- `sessions/<sessionId>/events.jsonl` — session event stream
- `sessions/<sessionId>/state.json` — latest saved agent state

Notes:

- some environment variables inside `state.json` and state events are encrypted through `EnvEncryptionService`
- the index and events are used to restore the history and state of interactive sessions

Format:

- `index.jsonl` and `events.jsonl` — JSONL
- `state.json` — JSON

### `misc/`

Directory for small internal CLI files.

Here, `junie` stores small internal files as separate key-based entries.

#### `misc/config_hashes.json`

Hashes of local custom skill configurations.

Used to track new, updated, and problematic local skill file configurations.

#### `misc/migration_state.json`

Migration state for user and project settings imported from other products.

Contains the list of already processed projects.

### `secure_credentials.json`

Fallback secret storage file.

It is used only when system secure storage is unavailable:

- macOS Keychain
- Windows Credential Manager
- Linux Secret Service

If fallback storage is enabled, secrets are stored in this file as JSON.

This is sensitive data.

### `mcp/mcp.json`

User MCP server configuration.

### `declined_mcps.json`

List of MCP servers declined by the user.

Format: JSON.

### `models/`

Custom user model profiles.

The CLI scans this directory for `*.json` files and loads model profiles from them.

### `agent-skills/`

User agent skills.

The CLI reads skills from:

- `<project>/.junie/agent-skills`
- `<junieHome>/agent-skills`

User files inside `junieHome` are stored in this directory.

## What may be stored outside `junieHome`

### `<project>/.junie/mcp/mcp.json`

Project-level MCP configuration.

It belongs to a specific project rather than global user state.

### `<project>/.junie/models`

Project-level custom model profiles.

These take priority over user profiles from `<junieHome>/models`.

## Short summary

If you only look at the CLI's global user data, the main locations are:

- `~/.junie/settings.json`
- `~/.junie/sessions/`
- `~/.junie/logs/`
- `~/.junie/misc/`
- `~/.junie/mcp/mcp.json`
- `~/.junie/declined_mcps.json`
- `~/.junie/models/`
- `~/.junie/agent-skills/`
- `~/.junie/secure_credentials.json` — only if system secure storage is unavailable

The most sensitive locations are:

- `secure_credentials.json`, if fallback storage is used
- the contents of `sessions/`, because they may contain work history and agent state
- user model profiles in `models/`, if they contain keys or custom headers