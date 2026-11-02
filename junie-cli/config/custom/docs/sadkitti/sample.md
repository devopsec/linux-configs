<!-- sadkitti-lint: ignore -->

# SAD KITTI — Real-World Sample Chain

### Nested jumps, IF/ELSE environment toggles, and missing-file ABORT fallback

This file demonstrates a realistic multi-hop retrieval scenario encountered when bootstrapping a deployment pipeline.
Read it sequentially; each `sadkitti` block is a self-contained directive executed before continuing.

---

## Step 1: Bootstrap — Require the Core Spec

The first thing any consumer must do is confirm the framework spec is available. If it isn't, nothing else can proceed
safely.

```sadkitti
REQUIRE "documentation/project/sadkitti/spec.md"
IF file is missing or unreadable -> ABORT with message: "Core spec unavailable — cannot bootstrap pipeline."
```

> ↩ Resume here once the spec is confirmed loaded.

---

## Step 2: Load Environment-Specific Configuration

Conditionally load production or staging guidelines based on the active deployment environment.

```sadkitti
IF active environment is "production"
  REFERENCE "documentation/agent/general-guidelines.md" AT SECTION "#Token Conservation"
  CACHE retrieved section in local state for all following blocks
ELSE
  REFERENCE "documentation/agent/general-guidelines.md" AT SECTION "#Context Window"
  CACHE retrieved section in local state for all following blocks
```

> ↩ Resume here with the environment-appropriate section pinned to cache.

---

## Step 3: Nested Jump — Drill into a Sub-Reference

After loading the top-level guidelines, jump to a sub-document for a specific technical detail, then return.

```sadkitti
REFERENCE "documentation/agent/bash-guidelines.md" AT SECTION "#Error Handling"
EXTRACT only the exit-code propagation rules
CACHE extracted rules in local state
```

> ↩ Resume with exit-code rules cached — no re-read of the full bash-guidelines file needed.

---

## Step 4: ABORT Fallback — Missing Legacy Section

Demonstrate the Interlock tripping on a deprecated or nonexistent target.

```sadkitti
IF section "#LegacyV1Endpoints" exists in "documentation/agent/general-guidelines.md"
  REFERENCE "documentation/agent/general-guidelines.md" AT SECTION "#LegacyV1Endpoints"
ELSE
  ABORT with message: "Section #LegacyV1Endpoints not found — legacy path deprecated. Use current API reference."
```

> ↩ Resume here only if the section existed. If `ABORT` fired, the pipeline branch halted cleanly.

---

## Step 5: Final Cache Confirmation

Pin all gathered context to avoid re-fetching during the remainder of the task.

```sadkitti
CACHE all retrieved content from Steps 1–4 in local session state
IF context window is approaching limit -> summarize cached content before proceeding
```

> ↩ Full, efficient local context established. Upstream token spend is minimized.

---

## Notes for Reviewers

- Each block is independently regex-extractable (`/```sadkitti\n([\s\S]*?)```/g`).
- The linter (`<project-root>/testing/integ/sadkitti_lint.py`) will flag any `REFERENCE`/`REQUIRE` path that doesn't exist on disk (run from project root).
- The graph tool (`<project-root>/testing/integ/sadkitti_graph.py`) will show this file as a leaf node with edges to
  `general-guidelines.md`, `bash-guidelines.md`, and `sadkitti/spec.md`.
