
## 7. Subagent model routing
Delegate by tier; the agent files in `~/.claude/agents/` set each model.
- Search, parsing, simple steps: `general-purpose` / `Explore` (haiku).
- Running tests, builds, linters: `test-runner` (haiku).
- Research and synthesis: `researcher` (sonnet).
- Planning: `Plan` (opus, high effort). Plan and code review: `reviewer` (opus).
- Implementation: `implementer` (sonnet); `implementer-hard` (opus) only for technically difficult or design-heavy steps.
