# Agent-Specific Documentation & Tuning

When creating a skill, you MUST research and document how specific agents (like Junie and Claude Code) should interact with the skill. While `SKILL.md` remains agent-neutral, the `agents/` folder contains Markdown files that tune the experience for specific platforms.

## Research Protocol
For every agent supported, you must research:
1. **Architecture**: Is it a CLI (like Junie CLI) or a web interface?
2. **Context Handling**: How does it manage the context window?
3. **Tool Availability**: Which MCP servers or built-in tools does it have?
4. **Formatting**: Does it have specific preferences for output (e.g., Markdown vs JSON)?

## Supported Agents

- **Junie (Junie CLI)**: Primary target for this repository.
- **Claude Code**: Anthropic's CLI agent.

## Documentation Standard
Use Markdown for all agent-facing documentation. The documentation should be stored in `agents/<agent-name>.md`.

### Recommended Sections:
- **Tuning**: How to prompt the agent specifically for this skill.
- **Overrides**: Instructions that differ from the main `SKILL.md`.
- **Tool Mapping**: How the skill's requirements map to the agent's available tools.
- **Performance**: Known edge cases or performance tips for this specific agent.

## Transition from YAML
Legacy `.yaml` configurations (like `openai.yaml` or `junie.yaml`) are being phased out in favor of descriptive Markdown. If a machine-readable configuration is strictly required, it should be documented in the agent-specific Markdown first.

## Prohibited Agents
- **OpenAI**: References to OpenAI-specific configurations or harnesses are no longer permitted in this repository.
