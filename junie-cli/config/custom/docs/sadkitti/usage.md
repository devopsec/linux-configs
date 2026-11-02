<!-- sadkitti-lint: ignore -->

# SAD KITTI — Agent Usage Guide

This guide covers how to interpret and execute SAD KITTI directives at runtime. For the full protocol specification,
see [`~/.junie/custom/docs/project/sadkitti/spec.md`](~/.junie/custom/docs/project/sadkitti/spec.md).

---

## 1. Recognizing a Directive Block

Any fenced code block with the language tag `sadkitti` is a **cognitive interrupt**. Upon encountering one:

1. Freeze your current position in the document.
2. Push the current document state and cursor location to working memory.
3. Execute the directives inside the block.
4. Pop the stack and resume at the line immediately after the closing ` ``` `.

Never skip or defer a `sadkitti` block — it may contain mandatory `REQUIRE` checks that gate everything following it.

---

## 2. Primitive Quick Reference

| Primitive   | Behavior                                                                  |
|-------------|---------------------------------------------------------------------------|
| `REFERENCE` | JUMP to the target file/section; absorb only the specified content.       |
| `REQUIRE`   | Mandatory dependency; trip the Interlock and `ABORT` if unresolvable.    |
| `CACHE`     | Pin retrieved content to active session context; avoid re-fetching later. |
| `IF / ELSE` | Conditional branch; load different references based on runtime state.     |
| `ABORT`     | Immediate circuit-breaker; emit the specified message and halt the branch.|

---

## 3. Interlock Safety Rules

- On any `REQUIRE` failure, execute `ABORT` immediately. **Do not guess or substitute content.**
- If a `REFERENCE` target section does not exist, treat it as an Interlock failure unless an `ELSE` branch is provided.
- Never silently ignore a missing dependency — always surface the error via `ABORT`.

---

## 4. Context Window Management

- Use `REFERENCE … AT SECTION` to absorb only the relevant subsection rather than the entire file.
- After a `CACHE` directive, do not re-fetch the same content — use the cached version.
- If the context window is approaching its limit, summarize cached content before loading new references.

---

## 5. Loading Order for This Project

When bootstrapping a task, load documentation in this order to maximize cache efficiency:

```sadkitti
REQUIRE "~/.junie/custom/docs/project/sadkitti/spec.md"
IF file is missing or unreadable -> ABORT with message: "SAD KITTI spec missing — cannot proceed."
```

Then load the relevant domain guideline for the current task:

```sadkitti
IF task domain is "bash"
  REFERENCE "~/.junie/custom/docs/bash/guidelines.md"
ELSE IF task domain is "python"
  REFERENCE "~/.junie/custom/docs/python-guidelines.md"
ELSE IF task domain is "infrastructure"
  REFERENCE "~/.junie/custom/docs/infrastructure-guidelines.md"
```

---

## 6. Worked Example

See [`~/.junie/custom/docs/project/sadkitti/sample.md`](~/.junie/custom/docs/project/sadkitti/sample.md) for a full multi-step chain
demonstrating nested jumps, environment toggles, and ABORT fallback handling.

---

## 7. Tooling Integration

Preferred global CLI (Junie home):

```bash
python3 ~/.junie/custom/scripts/agentmgr/agentmgr.py sadkitti lint .
python3 ~/.junie/custom/scripts/agentmgr/agentmgr.py sadkitti graph . --mermaid
python3 ~/.junie/custom/scripts/agentmgr/agentmgr.py sadkitti scan .
# or via slash command: /agentmgr sadkitti lint .
```

Project-local copies (still valid where present):

- **Linter**: `python3 <project-root>/testing/integ/sadkitti_lint.py .` — flags broken `REFERENCE`/`REQUIRE` paths (run from project root).
- **Graph**: `python3 <project-root>/testing/integ/sadkitti_graph.py .` — visualizes the documentation dependency network (run from project root).
- **Scan**: `python3 <project-root>/testing/integ/sadkitti_scan.py .` — dump blocks with file/line.

- **Lint ignore**: Add `<!-- sadkitti-lint: ignore -->` at the top of a file to exclude it from path checks
  (used in spec/sample files that contain illustrative, non-resolvable paths).
