# Junie CLI Specifics for RHEL Terminology Translate

## Context & Tuning

Junie CLI runs this skill as an on-demand Agent Skill loaded from `~/.junie/skills/`. The frontmatter `description` is the only thing kept in context before the skill triggers, so it must keep listing concrete non-RHEL terms/commands verbatim — Junie does not summarize or infer trigger intent beyond matching the description.

Junie has no built-in "MCP server for RHEL." If the user's session has no MCP tools matching the detection list in `SKILL.md` (`get_system_information`, `get_journal_logs`, `list_services`, `get_disk_usage`, etc.), treat this as a documentation/advisory-only session: answer from the reference tables and skip the "resolve RHEL version" MCP flow entirely unless a matching MCP server is configured for the current project.

## Instructions Overrides

- Do not use Junie's shell/terminal tools to execute the example commands in this skill (e.g., `dnf install`, `podman build`, `sudo rhel-drivers install`) unless the user is on a real RHEL host and explicitly asks for the command to be run. This skill is primarily conversational/advisory.
- When citing reference tables, prefer referencing the file path (e.g., "see `references/translation-tables.md#containers`") over reproducing entire tables in chat responses, consistent with Junie's context-conservation guidelines.

## Performance Notes

- Load only the relevant `### <Topic>` section of `references/translation-tables.md` for the user's question instead of opening the whole file when the topic is already obvious from the user's message.
- Reuse `references/file-paths-and-terminology.md` sparingly — it is small, so it can be loaded in full when a path or terminology question arises.
