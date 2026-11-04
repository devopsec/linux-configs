# Bootstrap templates

## Minimal `AGENTS.md`

```markdown
# Agent entrypoint — <project>

## Purpose
<one paragraph>

## Load guidelines

\`\`\`sadkitti
REQUIRE "documentation/agent/general-guidelines.md"
IF task is bash
  REFERENCE "documentation/agent/bash-guidelines.md"
IF task is python
  REFERENCE "documentation/agent/python-guidelines.md"
\`\`\`

## Project non-negotiables
- Do not commit unless the human explicitly asks
- Scratch files under `/tmp`
- Secrets never leave the repo

## Skills worth loading here
- <skill-name> — when ...
```

## Pointer to global parent (optional section)

```markdown
## Global fallback
User-level Junie docs live in `~/.junie/AGENTS.md` and `~/.junie/custom/docs/`.
Use them only when this project does not define a more specific rule.
```

## SAD KITTI domain router snippet

```sadkitti
IF task involves terraform or opentofu
  REFERENCE "documentation/agent/infrastructure-guidelines.md"
IF task involves tests or e2e
  REFERENCE "documentation/agent/testing-guidelines.md"
IF task involves security review
  REFERENCE "documentation/agent/security-guidelines.md"
```
