---
name: "dev-agents-skill-create"
description: "Create or update an Agent Skill. Use when asked to create a new skill, update an existing skill, or convert a recurring workflow into a reusable skill."
---

# Skill Creator

## About Skills

Skills are modular folders that extend Agent's capabilities by providing specialized knowledge, workflows, and tools. Think of them as "onboarding guides" for specific domains — they give the Agent project-specific context that no model can fully possess.

### What Skills Provide

1. **Specialized workflows** — multi-step procedures for specific domains
2. **Domain expertise** — project-specific knowledge, schemas, business logic
3. **Bundled resources** — scripts, references, and assets for complex or repetitive tasks

## Skill Locations

Skills are stored in a skills directory, per agent and per scope. The general format of the path is:

```
<scope-path><agent-dir>/skills/<skill-name>/
```

Below the currently supported agent directory and scope paths are expanded:

| Scope | Path | Usage |
|---|---|---|
| Project | `.junie/skills/<skill-name>/` | Junie Only |
| Shared | `$HOME/.junie/skills/<skill-name>/` | Junie Only |
| Project | `.agents/skills/<skill-name>/` | All Agents |
| Shared | `$HOME/.agents/skills/<skill-name>/` | All Agents |

**Always Ask** when creating a new skill where to store the skill. When updating a skill, default to the current location of the skill.

## Core Principles

### Concise is Key

The context window is a shared resource. Only add context Agent doesn't already have. Challenge each piece of information: "Does Agent need this, or does it already know it?" Prefer concise examples over verbose explanations.

### Set Appropriate Degrees of Freedom

- **High freedom** (text instructions): use when multiple valid approaches exist or decisions depend on context
- **Medium freedom** (pseudocode or parameterized patterns): use when a preferred pattern exists with some variation
- **Low freedom** (specific scripts, exact sequences): use when operations are fragile and consistency is critical

### Progressive Disclosure

Skills use a three-level loading system:

1. **Frontmatter** (`name` + `description`) — always in context; determines when the skill triggers
2. **SKILL.md body** — loaded when the skill triggers; keep under 500 lines
3. **Bundled resources** — loaded only when Agent determines they are needed

**Put all "when to use" information in `description`, not the body.** The body only loads after triggering.

## Directory Structure

```
<scope-path><agent-dir>/skills/<skill-name>/
├── SKILL.md           # Required: frontmatter + instructions
├── agents/            # Optional: Agent-specific documentation (junie.md, claude.md)
├── scripts/           # Optional: executable Bash/Python scripts
├── references/        # Optional: docs loaded into context as needed
└── assets/            # Optional: templates / output files (not loaded into context)
```

Do **not** create README.md, CHANGELOG.md, INSTALLATION_GUIDE.md, or other auxiliary files. The skill should contain only what Agent needs to do the job.

## Agent-Agnostic Goal

Skills should be designed to be agent-agnostic. General instructions live in `SKILL.md`, while agent-specific documentation, tuning, and overrides live in the `agents/` folder as Markdown files.

| File | Purpose |
|---|---|
| `SKILL.md` | Core instructions, workflows, and guidelines. Agent-neutral. |
| `agents/junie.md` | Tuning and overrides for Junie (Junie CLI). |
| `agents/claude.md` | Tuning and overrides for Claude Code. |

See [Agent Specifics](references/agent_configs.md) for research guidance.

## SKILL.md Format

```markdown
---
name: dev-agents-skill-create
description: What this skill does and when to use it. Include triggers here.
---

# Skill Title

[Body: instructions, workflows, checklists, references to bundled files]
```

**`name`** and **`description`** are the only required frontmatter fields.  
**`name`** must match the folder name exactly and follow the naming convention below. Segments are hyphen-separated; a segment may use camelCase when it is a multi-word token (`bestPractices`, `mcpServer`, `fixIssue`).  
**`description`** is the primary trigger mechanism — make it specific and comprehensive.

### Skill Naming Convention

Skill names follow this structure (BNF):

```bnf
<SKILL_NAME>          ::= <FUNCTIONAL_AREA> "-" <TARGET_PLATFORM> "-" <TARGET_OF_ACTION> "-" <ACTION>
<FUNCTIONAL_AREA>     ::= <alphanum>+
<TARGET_PLATFORM>     ::= <alphanum>+
<TARGET_OF_ACTION>    ::= <alphanum>+
<ACTION>              ::= <alphanum>+
<alphanum>            ::= [0-9a-zA-Z]
```

| Segment | Purpose | Examples |
|---|---|---|
| `FUNCTIONAL_AREA` | Broad category of the skill | `vcs`, `dev`, `docs`, `sec`, `gfx`, `web`, `misc` |
| `TARGET_PLATFORM` | Tool, platform, or language targeted | `github`, `git`, `bash`, `notion`, `frontend`, `mcp` |
| `TARGET_OF_ACTION` | The thing being acted on | `pr`, `commit`, `script`, `image`, `skill`, `ui`, `any` |
| `ACTION` | What is done to the target | `create`, `review`, `merge`, `read`, `update`, `manage`, `maintain` |

**Examples:**

| Skill | Breakdown |
|---|---|
| `vcs-forge-pr-create` | version control -> forge (multi-forge CLI) -> pull request -> create |
| `dev-bash-script-review` | development -> Bash -> script -> review |
| `gfx-lmstudio-image-create` | graphics -> LM Studio -> image -> create |
| `docs-notion-knowledge-capture` | documentation -> Notion -> knowledge -> capture |
| `infra-opentofu-any-manage` | infrastructure -> OpenTofu -> multiple targets -> manage |

**Guidance:**

- `SKILL_NAME`: If the skill spans multiple functional areas or the functional area is not clear, fallback to "misc"
- `FUNCTIONAL_AREA`: If the skill targets multiple platforms or the platform is unclear, fallback to one of (best fit):
  + *type* of platform targeted
  + group of *things* skill is targeting
  + protocol being targeted
- `TARGET_PLATFORM`: If there are multiple targets for the actions(s) the skill targets, fallback to "any"
- `TARGET_OF_ACTION`: If there are multiple actions being targeted, fallback to a more general action, such as:
  + manage
  + administer
  + process

## Skill Creation Process

### Step 1: Understand the Skill

Identify concrete examples of how the skill will be used. Key questions:
- What task does this skill support?
- What would a user say to trigger it?
- What knowledge or resources would make repeated execution more reliable?

### Step 2: Plan Reusable Contents

For each example, consider:
- What code gets rewritten repeatedly -> candidate for `scripts/`
- What context must be re-discovered each time -> candidate for `references/`
- What boilerplate or templates are needed -> candidate for `assets/`

### Step 3: Create the Skill

Use the `init_skill.py` script to bootstrap the skill directory structure:

```bash
python3 .agents/skills/dev-agents-skill-create/scripts/init_skill.py <skill-name> --path <scope-path><agent-dir>/skills
```

This will create `SKILL.md`, `agents/junie.md`, `agents/claude.md`, and the necessary resource directories.

### Step 4: Write SKILL.md

- Keep the body focused on procedural instructions and workflow guidance
- Move detailed reference material (schemas, API docs, checklists) to `references/` files
- Reference bundled files explicitly in the body and describe when to load them
- Keep each reference file under 500 lines; add a table of contents for longer files
- Avoid deeply nested references — keep all reference files one level from `SKILL.md`

### Step 5: Validate

Run the validation script to ensure the skill follows the standard and safety requirements:

```bash
python3 .agents/skills/dev-agents-skill-create/scripts/validate.py <path-to-skill>
```

The script checks:
- [ ] YAML frontmatter in `SKILL.md`
- [ ] Hyphen-case naming convention
- [ ] Safety checks (dangerous commands, hardcoded secrets, credential/config file access, agent identity file access, obfuscation)
- [ ] Permission scope (network calls, commands, executable files) and an overall risk classification (LOW/MEDIUM/HIGH/EXTREME)
- [ ] Existence of agent-specific documentation
- [ ] Absence of legacy OpenAI configurations
- [ ] Proper folder structure

### Step 6: Audit External Skills (imported/untrusted code only)

This step applies whenever a skill was **not** authored in this workflow — copied from a download, another repo, ClawdHub, GitHub, or shared by another agent. See [Trust Model](#trust-model) below. Skip this step for skills you wrote yourself in Steps 1-5.

1. Generate the audit report before the skill is installed:

```bash
python3 .agents/skills/dev-agents-skill-create/scripts/audit_skill.py <path-to-not-yet-installed-skill>
```

   This writes `AUDIT.md` next to the skill (threat analysis, code analysis, permission scope, risk classification, and validation results — all derived from concrete, reviewable checks in `scripts/`, not from source reputation).

2. Show the full `AUDIT.md` to the user and get an explicit approve/reject decision. If the user is concerned about specific findings, start an interactive session to dig further into those specific files before they decide.
3. **If rejected:** do not install. Archive it instead of deleting it, so it stays available for further review:

```bash
python3 .agents/skills/dev-agents-skill-create/scripts/audit_skill.py <path-to-skill> --archive-rejected --reason "<why>"
```

4. **If approved:** proceed to Step 7 (Final Human Review) before copying it into the target skills directory.

### Step 7: Final Human Review (required for every skill)

Regardless of whether a skill was self-authored (Steps 1-5) or imported (Step 6), it must receive one last explicit human sign-off before it is considered installed:

- Present the finished skill's complete file listing/contents (not just previously flagged parts) to the user.
- Obtain explicit approval. Only after that approval is the skill considered installed/done.
- No skill is ever added without this step — there is no exception for "trusted-looking" or low-risk skills.

### Step 8: Iterate

After real usage, notice struggles or inefficiencies, then update the skill accordingly.

## Trust Model

We trust code we wrote ourselves in this workflow, and nothing else:

- **Self-authored code** (written by the agent during Steps 1-5, e.g. via `init_skill.py`) is exempt from Step 6's audit/approval gate, but still requires the Step 7 final human review before it's considered installed.
- **Any other code** — downloaded, copied, or otherwise sourced externally — is untrusted, full stop. This includes "official", high-star, or well-known sources: reputation is not a substitute for review. There is no tiered scrutiny based on source; every imported skill goes through the identical Step 6 audit.
- Risk classification (`validate.py`'s `classify_risk`) is computed purely from what is found in the skill's own files (dangerous patterns, credential/identity access, network scope) — never from who published it or how popular it is.

## Environment Context

When writing skills for this project, be aware of:

- **IDE:** JetBrains PyCharm with Agent MCP tools available (file read/write, search, run configurations, build, terminal)
- **Available MCP servers** (when configured): GitHub, Playwright, Notion, Linear, Sentry, and others — reference by name if a skill involves them
- **Project guidelines:** `documentation/agent/general-guidelines.md`, `documentation/agent/bash-guidelines.md`, `documentation/agent/python-guidelines.md`
- **Communication preference:** Ask questions inline as numbered lists; do not use multi-select prompt UI
- **No commits:** Agent does not commit. The user reviews and submits all changes.
- **Credentials:** This repo contains private credentials. Never reference or expose them outside the repo.

