# Tracker patterns

Load when the project’s TODO layout is unclear.

## Common file layouts

### Single markdown ledger

```markdown
# TODOs

## Open
### todo-a1b2c3d4 — Short title
- **Context:** ...
- **Acceptance:**
  - [ ] ...
- **Links:** path/or/spec.docx
- **Notes:** ...

## Done
### todo-a1b2c3d4 — Short title (done)
- Completed: <summary of what shipped>
```

### Table ledger

```markdown
| ID | Status | Title | Area | Links |
|----|--------|-------|------|-------|
| todo-a1b2c3d4 | open | Add CDR export | isen | docs/... |
```

Status edits: update the `Status` cell; optionally add a `Completed` column.

### Checkbox lists

```markdown
- [ ] todo-...: description
- [x] todo-...: description
```

## Status transitions

| From | To | When |
|------|----|------|
| open | in-progress | You start work (optional; only if file uses it) |
| open / in-progress | done | Acceptance met + verified |
| open | blocked | Missing dependency; note blocker |
| any | cancelled | User declines; note reason |

Keep historical ids. Prefer moving sections over deleting rows so grepping old sessions still works.

## Id discovery

Search order:

1. User-provided id
2. `todo-[a-f0-9]{6,}` in trackers
3. Open checkboxes / `Status: open`
4. In-code `TODO(todo-...)` cross-refs

## Linking code comments to trackers

Good:

```c
/* TODO(todo-a1b2c3d4): emit reason code 42 on upstream timeout */
```

When done: remove the comment or point at the permanent design note — not at the closed todo id alone.
