# Guidelines and memory

<show-structure depth="3" for="chapter"/>

## Guidelines

Guidelines allow you to provide persistent, reusable context to the agent. Junie CLI reads guidelines 
from the `AGENTS.md` file and adds this context to every task it works on.

Additionally, Junie CLI checks for any guidelines or memory files from other AI agents when it opens the project
for the first time. If such files are detected, it will suggest importing the instructions into `.junie/AGENTS.md`.

### AGENTS.md

[AGENTS.md](https://agents.md/) is an open file format for guiding coding agents. It's a standard Markdown file 
with headings, lists, and plain text that the agents can parse to add to the prompt context. 

[//]: # (For user-defined instructions and project context, Junie CLI reads the `.junie/AGENTS.md` file at the root of your project.)

### How Junie CLI discovers guidelines

When Junie CLI starts a task, it looks for guidelines in the following order:

1. `.junie/AGENTS.md` file in the project root.
2. `AGENTS.md` file in the project root.
3. `.junie/guidelines.md` file or `.junie/guidelines/` folder – Junie's legacy format for guidelines (still supported).

<procedure title="Examples of guidelines">

An `AGENTS.md` file can include project-specific context such as tech stacks, conventions, or rules.
Providing this information helps Junie better understand your environment, avoid incompatible libraries,
and follow your project's specific architectural patterns.

Below are some examples of what you can include:

* **Quick-start checklist:**

```markdown
# A short bullet list of the most critical rules the agent must follow before doing anything

- [ ] Read this file and `README.md` before acting.
- [ ] Update `CHANGELOG.md` for user-facing changes.
```

* **Local development commands**:

```markdown
# A table or list of project-specific commands for install, lint, test, build, and span dev server

| Task                 | Command        |
|----------------------|----------------|
| Install dependencies | `pnpm install` |
| Start dev server     | `pnpm dev`     |
| Run unit tests       | `pnpm test`    |
```

* **Feature development and decision making:**

```markdown
# Feature development and decision making

- Make small, targeted changes instead of building for hypothetical future needs.
- If something is unclear, ask before making assumptions.
```

* **UI and architecture:**

```markdown
# UI and architecture guidelines

- Use existing design system components.
- Avoid inline styles.
- Follow current domain boundaries.
- Prefer extending existing services.
```

* **Security and data handling:**

```markdown
# Security and data handling

- Never log tokens or sensitive data.
- Sanitize all user input and use existing auth middleware.
```

* **Testing and contribution:**

```markdown
# Testing and contribution

- Add unit tests for new business logic.
- Keep changes minimal and avoid large refactors in feature tasks.
- Do not rename files without a valid technical reason.
```

* **Non-goals for agents:**

```markdown
# Explicit prohibitions what agents must NOT do 

- Do not bump major versions of core dependencies without a dedicated PR and discussion.
- Do not change database schema without a corresponding migration file.
```

For more technology-specific examples of guidelines with explanations, see the 
[junie-guidelines](https://github.com/JetBrains/junie-guidelines) catalog.
</procedure>


[//]: # (## Memory)

[//]: # ()
[//]: # (TBD)