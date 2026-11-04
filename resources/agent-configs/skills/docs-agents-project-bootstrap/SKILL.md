---
name: "docs-agents-project-bootstrap"
description: "Bootstrap or refresh a repository's agent documentation: AGENTS.md, guideline trees, SAD KITTI routing, skills pointers, and Junie/project agent entrypoints. Use when onboarding a repo for agents, propagating ~/.junie parent docs, adding AGENTS.md, or aligning project agent instructions with global guidelines."
---

# Agents project bootstrap

Stand up **project-level** agent docs so Junie (and other agents) load the right rules without dumping global noise.

## When to use

- New repo needs `AGENTS.md` / `.junie/` / `.agents/`
- "Update agent instructions from parent documentation"
- Propagate SAD KITTI or guideline layout into a project
- Align skills discovery paths

## Discover first

```sadkitti
REQUIRE "~/.junie/AGENTS.md"
REFERENCE "~/.junie/custom/docs/general-guidelines.md" EXTRACT high-level rules only
IF project already has AGENTS.md
  REFERENCE project "AGENTS.md"
  CACHE existing structure — extend, do not clobber custom sections without cause
IF project has documentation/agent/ or .junie/custom/docs/
  REFERENCE that tree's index or README
```

Also check: `.agents/`, `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md` — link or defer, do not fight them.

## Target layout (adaptive)

Prefer the repo’s existing documentation root. If none:

```text
AGENTS.md                          # entrypoint (or .junie/AGENTS.md if project standard)
documentation/agent/               # OR .junie/ / docs/agent/
  general-guidelines.md            # project overlays only
  bash-guidelines.md               # only if bash is used
  ...
  sadkitti/                        # optional local spec pointer
.junie/skills/                     # optional project skills
.junie/commands/                   # optional project commands
```

Global user skills stay in `~/.junie/skills/`; project skills only for repo-specific rituals.

## Workflow

1. **Inventory** languages, infra, test tools, credential-handling needs.
2. **Write/update `AGENTS.md`**
   - Project purpose (1 short paragraph)
   - How to load guidelines (SAD KITTI blocks)
   - Pointers to skills/commands relevant here
   - Non-negotiables (no commit, credentials, scratch in `/tmp`)
3. **Add thin guideline files** only for domains the repo uses — do not copy entire `~/.junie/custom/docs/` verbatim.
4. **SAD KITTI** — entrypoint routes to domain files; keep primitives consistent with [references/bootstrap-template.md](references/bootstrap-template.md).
5. **Verify** paths resolve; open entrypoint as a fresh agent would.
6. **Report** files created/changed and what was intentionally not copied.

## Rules

- **Extend > replace** when project docs exist.
- Project overrides global on conflict; state that explicitly in `AGENTS.md`.
- No credential material in agent docs.
- Do not register every global skill — only those that apply.

## References

- [references/bootstrap-template.md](references/bootstrap-template.md) — AGENTS.md skeleton + SAD KITTI samples
- [references/propagation-checklist.md](references/propagation-checklist.md) — copy vs pointer decisions

## Global pointers

- Parent entry: `~/.junie/AGENTS.md`
- Catalogs: `~/.junie/custom/docs/skills-catalog.md`, `commands-catalog.md`
- SAD KITTI: `~/.junie/custom/docs/sadkitti/`
