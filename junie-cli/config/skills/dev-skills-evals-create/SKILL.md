---
name: dev-skills-evals-create
description: "Evaluate whether agent skills trigger for the right prompts, route references correctly, and improve task results. Use when users ask for skill-trigger tests, router evaluation, reference routing, golden tasks, or a Junie headless trigger run."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: []
  license: MIT
---

# Agent Skill Evaluation

Measure skill behavior separately from structural validation: whether the right skill loads, whether sibling skills are confused, and whether the skill improves a checked task.

## Triggers

- Agent skill trigger precision/recall, near-miss prompts, reference routing, or skill A/B evaluation.
- Junie CLI headless evaluation over a staged skill catalog.

## Load order (SAD KITTI)

```sadkitti
IF file exists "~/.junie/custom/configs/dev/skills-evals.toml"
  REFERENCE "~/.junie/custom/configs/dev/skills-evals.toml"
ELSE
  USE the tool defaults listed below
IF task involves skill triggers, SAD KITTI references, or golden tasks
  REFERENCE "references/skill-evals.md"
IF task asks to run Junie trigger prompts
  REFERENCE "scripts/trigger_eval.py"
CACHE only the loaded evaluation choices for this task
```

## Workflow

1. Build a redacted JSONL set with positive, sibling near-miss, and unrelated negative prompts; set `expect` to one skill name or `null`.
2. Run offline catalog checks first, then use the bundled Junie runner only with a disposable project and a copied/staged skills root.
3. Use at least three runs per prompt; compare observed loads with expected skills and inspect confusion pairs before editing descriptions.
4. Run golden tasks with and without the skill using fresh fixtures and an unchanged checker; keep results in temporary or CI artifacts.

## Tool defaults

- Use Junie CLI one-shot piped-input mode with `--input-format text`, `--output-format json`, an isolated `JUNIE_HOME`, and default skill locations disabled.
- Read `JUNIE_API_KEY` from the environment and pass it only to Junie's documented `--auth` flag; that value is briefly visible in process arguments, so use a single-user isolated runner and never log the command.
- Live runs can incur provider cost and create transcripts. Require both `--yes` and `--isolated-runner`; never use a working repository or real user data as the fixture.
- The optional runner defaults are shown in `assets/config.example.toml`; do not create files under `~/.junie/custom/` automatically.

## Related skills

- Structural skill checks and imported-skill review → `dev-agents-skill-create`.
- Agent behavior and tool-call evaluation → `dev-agents-evals-create`.
