# Evaluating our own Agent Skills

Not from upstream — local addition. Structural/safety checks stay in `dev-agents-skill-create` (Step 5 `validate.py`, Step 6 audit); this file measures *behaviour*: does the skill trigger when it should, stay quiet when it shouldn't, and make the agent better at the task?

## Contents

1. What to measure
2. Trigger dataset
3. Offline trigger eval (router simulation)
4. Live trigger eval (Claude Code / Junie)
5. Golden tasks (A/B vs baseline)
6. Interpreting and fixing
7. Where to keep it

## 1. What to measure

| Metric | Definition | Target (start) |
|---|---|---|
| Trigger recall | should-trigger prompts where the skill was loaded | ≥ 0.9 |
| Trigger precision | loaded-skill events that were expected | ≥ 0.9 |
| Confusion | prompts routed to a *sibling* skill instead (e.g. `sec-llm-io-guard` vs `sec-junie-guardrails-manage`) | list, fix top pairs |
| Reference routing | correct `references/*.md` loaded via the SAD KITTI branch, and no unneeded ones | ≥ 0.8 |
| Golden-task pass rate | task checker passes with skill vs without | skill ≥ baseline + meaningful delta |
| Cost | tokens / steps with vs without skill | not worse without benefit |

## 2. Trigger dataset

`evals/skills/<skill-name>/triggers.jsonl`, 20–40 rows per skill:

```jsonl
{"id": "p1", "prompt": "add an eval gate for our tool-calling agent in Cloud Build", "expect": "dev-agents-evals-create", "kind": "positive"}
{"id": "p2", "prompt": "check whether the kamailio skill triggers on 'pike limits'", "expect": "dev-skills-evals-create", "kind": "positive"}
{"id": "n1", "prompt": "create a new skill for terraform drift", "expect": "dev-agents-skill-create", "kind": "near-miss"}
{"id": "n2", "prompt": "rename this python variable", "expect": null, "kind": "negative"}
```

Mix: ~50% positive (paraphrases, synonyms, tool/file names from the description, terse and verbose), ~30% near-miss (sibling skills' territory), ~20% unrelated negatives. Write prompts the way users actually do; mine real ones from past sessions (`session-history` skill: `~/.junie/sessions/index.jsonl`, then `transcript.md`) — redact secrets/PII before committing.

## 3. Offline trigger eval (router simulation)

Cheap, deterministic-ish, runs in CI without an agent. Build the catalog exactly as the agent sees it (name + description from each `SKILL.md` frontmatter), then ask a judge model per prompt: "Which skill (or none) would you load? Answer with the name only." Temperature 0, n=3 votes.

```python
import pathlib, yaml

def catalog(skills_root: str) -> list[dict]:
    out = []
    for f in sorted(pathlib.Path(skills_root).glob("*/SKILL.md")):
        fm = yaml.safe_load(f.read_text().split("---")[1])
        out.append({"name": fm["name"], "description": fm["description"]})
    return out

def score(skill: str, rows: list[dict], picks: dict[str, str | None]) -> dict:
    tp = sum(1 for r in rows if r["expect"] == skill and picks[r["id"]] == skill)
    fp = sum(1 for r in rows if r["expect"] != skill and picks[r["id"]] == skill)
    fn = sum(1 for r in rows if r["expect"] == skill and picks[r["id"]] != skill)
    return {"precision": tp / (tp + fp or 1), "recall": tp / (tp + fn or 1),
            "confusions": [(r["id"], picks[r["id"]]) for r in rows if picks[r["id"]] != r["expect"]]}
```

Run it against the *staged* catalog (new skill + all existing ones) so collisions surface before install. Limitation: approximates, does not reproduce, the agent's real selection logic — confirm with §4 before trusting small deltas.

## 4. Live trigger eval

**Claude Code** (headless; verify flags with `claude --help` for your version):

```bash
claude -p "<prompt>" --output-format stream-json --verbose \
  --allowedTools "Read,Grep,Glob,Skill" > "/tmp/skill-evals/<id>.jsonl"
```

- Parse `tool_use` events: a `Skill` tool call (or a `Read` of `.../skills/<name>/SKILL.md`) = triggered; `Read` of `references/*.md` = reference routing.
- Restrict tools to read-only so trigger runs cannot modify anything; run in a throwaway checkout.
- Baseline without skills: `--disable-slash-commands` (disables skills and commands).

**Junie CLI** (headless options checked 2026-10-28): use `python scripts/trigger_eval.py <triggers.jsonl> --skills-root <staged-catalog> --dry-run` to validate inputs. For a live run, add `--runs 3 --yes --isolated-runner`; the runner uses documented `--auth`, `--input-format text`, `--output-format json`, `--project`, `--session-id`, skill/config isolation, `--cache-dir`, `--max-steps`, and `--skip-update-check` options. It copies the catalog, sets a temporary `JUNIE_HOME`, reads each prompt from stdin, and parses the isolated session transcript for `agent_skill_read_doc` calls. `JUNIE_API_KEY` is passed through the CLI's `--auth` argument and is briefly visible to same-user processes; use only a disposable single-user runner, never log the command, and never include real secrets or PII in fixtures. Local `junie --help` should be checked before running because the available CLI build may differ from the reference.

Run each prompt n≥3; a trigger counts if it occurs in the majority.

## 5. Golden tasks (A/B vs baseline)

`evals/skills/<skill-name>/golden/<task-id>/`:

```
task.md        # the user prompt, verbatim
fixture/       # minimal repo state the task starts from (copied fresh per run)
check.sh       # exit 0 = pass; programmatic checks on the result (files, validator output, tests)
rubric.md      # optional judge rubric for qualitative parts (follows house style? cites references?)
```

- 5–10 tasks per skill covering its main workflow branches and one safety case (e.g. must refuse to print secrets, must not commit).
- Run each task in two arms: **with skill** and **without** (Claude: `--disable-slash-commands`; Junie: skill removed from a scratch skills dir). Same model, same fixture, n≥3.
- Record pass rate, steps, tokens, and judge score per arm. A skill that doesn't beat baseline on its own golden tasks is a candidate for rewrite or removal.
- For skills that create skills (e.g. `dev-agents-skill-create`), `check.sh` should run `validate.py` on the produced folder and assert naming/frontmatter rules.

`check.sh` follows the Bash guidelines (`#!/usr/bin/env bash`, `set -euo pipefail`, quoted vars, non-interactive, no network unless the task needs it).

## 6. Interpreting and fixing

| Finding | Usual fix |
|---|---|
| Low recall | add user vocabulary, tool names, file names to the `description` (the only text seen before loading); "Use when …" clause first-class |
| Low precision / sibling confusion | sharpen scope in both descriptions; add "not for X — use `<sibling>`" to the narrower one; move shared material to one skill and cross-link |
| Wrong references loaded | make SAD KITTI `IF` conditions concrete (tool/file names), split oversized references |
| Golden task fails with skill | the skill's workflow is wrong or stale — fix content, re-run, never weaken `check.sh` |
| No delta vs baseline | skill restates model knowledge; cut to gotchas, exact commands, local conventions |

Re-run §3 after every description change; re-run §4/§5 before installing into `~/.junie/skills/`.

## 7. Where to keep it

Eval assets live beside the skill source in the repo that owns it (e.g. `.commonai/skills/<name>/evals/` or a top-level `evals/skills/`), not in `~/.junie/skills/`. Results (`/tmp` or CI artifacts) are not committed except the reviewed baseline summary.
