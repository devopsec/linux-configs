---
name: dev-agents-evals-create
description: "Design and improve evaluations for tool-using agents and LLM applications. Use when users ask for agent evals, tool-choice tests, adversarial or safety cases, promptfoo suites, judge calibration, eval gates, or drift tracking."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/ai/agent-evals
  license: MIT
---

# Agent Evaluation

Create repeatable evaluations that test observable behavior, not matching prose. Prefer deterministic checks; use judges only for open-ended quality.

## Triggers

- Agent or LLM evaluation, tool selection and argument correctness, multi-step task outcomes.
- Safety and adversarial fixtures, judge rubrics, promptfoo, evaluation gates, or drift comparisons.

## Load order (SAD KITTI)

```sadkitti
IF file exists "~/.junie/custom/configs/dev/agent-evals.toml"
  REFERENCE "~/.junie/custom/configs/dev/agent-evals.toml"
ELSE
  USE the tool defaults listed below
IF task involves agent evaluation design or fixtures
  REFERENCE "references/agent-evals.md"
CACHE only the loaded evaluation choices for this task
```

## Workflow

1. Define a user-visible outcome, risks, and evaluation layer; use exact/schema/programmatic checks before an LLM judge.
2. Create independent positive, negative, and adversarial fixtures with stable expected results; protect held-out cases.
3. Repeat stochastic cases, measure false tool calls and task outcomes, calibrate judges against human labels, and record model/version context.
4. Gate safety regressions in CI; review any baseline update instead of changing expected values to force a pass.

## Tool defaults

- Use `pytest` for deterministic tool-choice and result checks; `promptfoo` 0.125.1 (checked 2026-10-28) for provider-driven suites, with Node ≥ 22.22.
- Use a pinned, separate judge model for open-ended scoring; keep credentials in the runner environment or Secret Manager.
- Store fixtures and reviewed baselines with the owning application; do not commit raw user prompts or sensitive results.
- Optional tool preferences are illustrated in `assets/config.example.toml`; do not create global config files automatically.

## Related skills

- Skill trigger and golden-task evaluation → `dev-skills-evals-create`.
- Retrieval-specific metrics → `dev-rag-evals-create`.
- Agent prompt-injection cases → `sec-agents-promptInjection-defend`.
