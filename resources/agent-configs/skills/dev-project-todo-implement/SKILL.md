---
name: "dev-project-todo-implement"
description: "Implement a tracked or in-code TODO end-to-end: resolve the item from a project TODO tracker (todo.md / todo-<id>) or from TODO/FIXME/XXX comments in source, implement the change, then update project documentation and the tracker/comment status. Use when asked to implement a todo, close a tracker item, finish a TODO comment, or work from documentation/project/trackers."
---

# Project TODO Implement

Turn one concrete TODO into working code **and** keep docs/tracker state honest.

## Triggers

- `implement todo-<id>`, `from project documentation`, tracker paths like `documentation/project/trackers/todo.md`
- Source markers: `TODO`, `FIXME`, `XXX`, `HACK` with actionable text
- "close this todo", "implement the next open tracker item"

## Sources (pick one primary)

| Source | How to locate | Status update target |
|--------|---------------|----------------------|
| **Tracker** | `todo.md`, `TODO.md`, `documentation/project/trackers/**`, issue boards mirrored in-repo | Tracker row / section for that id |
| **In-code comment** | Search `TODO|FIXME|XXX` near the path/symbol the user named | Comment itself (remove, or mark `DONE` / replace with brief note) |
| **Mixed** | Tracker links to files/comments | Both tracker **and** comment |

If the user gives only a vague "todos", list open candidates (id + one-line summary) and ask which to take — do not batch-implement without agreement.

## Workflow

1. **Resolve the TODO**
   - Tracker: open the tracker file; find `todo-<id>` (often 8–12 hex) or the titled section; read acceptance criteria, linked specs, and paths.
   - Comment: open the file; capture the full comment block and surrounding code contract.
   - Load linked specs/docs only as needed (DOCX/MD/OpenAPI). For DOCX-heavy specs, prefer `docs-docx-document-edit` for extraction, then this skill for implementation routing.
   - Write a short **definition of done** (3–7 bullets) before coding.

2. **Map touchpoints**
   - Locate code paths named by the TODO; if the monorepo has a sibling platform ("as in contract-X"), diff that reference implementation first.
   - Note tests, install/configure scripts, and docs that must move with the change.

3. **Implement**
   - Minimal change that satisfies the definition of done.
   - Follow project guidelines (`AGENTS.md`, language guidelines via SAD KITTI / project docs).
   - Add or update tests when the TODO implies behavior; skip only for pure docs/comments.

4. **Verify**
   - Run the narrowest meaningful check (unit test, script `--help`, build target, lint).
   - Confirm edge cases called out in the TODO.

5. **Update documentation (required)**
   - Tracker: mark item done/cancelled with date-free factual status; move to a Done section if the file uses one; keep ids stable.
   - In-code: remove the TODO or replace with a precise comment only if residual context is still needed.
   - Project docs: update README / module docs / changelog **when behavior, CLI, config, or public contracts changed**.
   - Cross-links: if the TODO referenced a spec section, note completion next to that reference if the project keeps a requirements matrix.
   - Do **not** invent docs structure — match existing layout. If docs are missing and behavior changed, add the smallest accurate note in the nearest existing doc.

6. **Handoff**
   - Summarize: what changed, docs/tracker updates, how verified, residual risks.
   - Offer a commit-message draft only; do not commit (see `vcs-git-commit-create`).

## Tracker conventions (adaptive)

Projects differ; detect rather than assume:

- **Id form:** `todo-<hex>`, `TODO-123`, GitHub-style `#123`, or bare section headings.
- **Status vocabulary:** open / in-progress / done / blocked / cancelled — mirror the file's existing words.
- **Common paths to try:** `documentation/project/trackers/todo.md`, `docs/todo.md`, `TODO.md`, `.github/TODO.md`.

See [references/tracker-patterns.md](references/tracker-patterns.md) for layouts and status-edit patterns.

## In-code TODO conventions

- Prefer fixing the root cause over leaving `TODO (done)`.
- If deferring part of the work, split: implement agreed scope; leave a **new** sharper TODO for the remainder (do not silently shrink scope).
- Never delete a TODO that tracks a security or data-loss hazard without implementing or explicitly escalating to the user.

## Documentation update checklist

After implementation, tick all that apply:

- [ ] Tracker status reflects reality
- [ ] Source TODO comment resolved or narrowed
- [ ] User-facing docs match new behavior (flags, env, APIs)
- [ ] Internal architecture/notes updated if control flow changed
- [ ] Examples/snippets still run
- [ ] Outdated "not yet implemented" claims removed

## Anti-patterns

- Implementing without reading linked acceptance criteria
- Marking tracker done while tests fail
- Updating code but leaving README claiming the feature is absent
- Mass-closing TODOs unrelated to the request
- Committing or pushing

## References

- [references/tracker-patterns.md](references/tracker-patterns.md) — tracker schemas, status transitions
- [references/doc-update-map.md](references/doc-update-map.md) — which docs to touch by change type

## Related skills

- `dev-project-spec-implement` — when the TODO is mostly "build from this spec"
- `docs-project-documentation-update` — broader doc drift beyond the TODO's docs
- `vcs-git-commit-create` — message-only handoff after implementation
