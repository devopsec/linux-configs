---
name: "docs-project-documentation-update"
description: "Review and update project documentation for accuracy: sync README with the repo, refresh module docs, find outdated or contradictory docs, fix broken links, and align docs with recent commits and code. Use when asked to update the README, organize documentation, fix outdated docs, or documentation drift."
---

# Project documentation update

Make docs match the **current** tree — not a rewrite for its own sake.

## Scope modes

| Mode | Intent |
|------|--------|
| **readme-sync** | README (+ quickstart) matches build/run/test reality |
| **outdated-sweep** | Find stale claims across docs/ |
| **organize** | Restructure headings/nav without losing content |
| **post-feature** | Document what just shipped |
| **link-repair** | Broken relative links and anchors |

Infer from the user; default to **readme-sync** + light outdated-sweep on touched areas.

## Workflow

1. **Inventory**
   - Doc roots: `README*`, `docs/`, `documentation/`, `*.md` in packages, man pages, mkdocs/sphinx config.
   - Recent truth sources: `git log -20 --oneline`, key manifests (`package.json`, `pyproject.toml`, `CMakeLists.txt`, `Makefile`), `--help` of main CLI.

2. **Extract claims**
   - Commands, ports, paths, versions, feature availability, env vars.
   - Build a short claim list in `/tmp` when large.

3. **Verify claims**
   - Prefer running cheap checks (`--help`, list dirs, open referenced files).
   - Mark: `ok` / `stale` / `missing` / `unknown`.

4. **Update**
   - Fix stale claims; remove or qualify unknowns.
   - Match existing tone and heading style; no drive-by voice change.
   - Preserve intentional historical sections (changelogs) — mark as historical if needed.
   - Update nav/index pages if files move.

5. **Outdated detection heuristics**
   - Paths that no longer exist
   - Flags not in `--help` / argparse
   - "Coming soon" for code that exists (or reverse)
   - Old package managers or Python/Node versions vs pins
   - Screenshots/diagrams that contradict UI (flag for user if binary)

6. **Finish**
   - Summarize files changed + remaining doc debt.
   - No commit unless asked.

Load [references/outdated-heuristics.md](references/outdated-heuristics.md) for sweep checklists and [references/readme-structure.md](references/readme-structure.md) when rebuilding README sections.

## Rules

- **Code wins** over docs when they conflict, unless the user says docs are the spec (then use `dev-project-spec-implement`).
- Do not invent features in docs.
- Do not mass-reformat unrelated markdown.
- Keep credentials and internal hostnames out of public README if the repo is public — follow existing sensitivity.

## Related

- Agent entrypoint docs → `docs-agents-project-bootstrap`
- Normative API specs → `dev-project-spec-implement`
