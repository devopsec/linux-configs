---
name: dev-zig-code-review
description: "Review, audit, or assess Zig code, build.zig, and build.zig.zon for correctness, memory safety, error handling, illegal behavior, concurrency (std.Io), API design, version drift, tests, and style — optionally against TigerStyle. Use when asked to review/audit/check Zig code or a Zig PR/diff, look for leaks/UB/bugs in Zig, assess whether Zig code is idiomatic or up to date for its Zig version, or apply TigerStyle/TigerBeetle guidelines. For writing or fixing code use dev-zig-code-create; for version upgrades use dev-zig-version-migrate."
---

# Zig code review

Find real defects first (leaks, illegal behavior, swallowed errors, races, version drift), then
design and style. Every finding cites `file:line`, explains the failure scenario, and proposes a
concrete fix that is valid for the project's Zig series.

## Ground rules

- Establish the Zig series before judging APIs: `../dev-zig-code-create/scripts/zig-env.sh <project>`
  (pinned `minimum_zig_version` wins over the installed compiler). Code valid for 0.14 is not
  "wrong" in a 0.14 project — flag drift as such, not as a bug.
- Scripts produce **leads**; confirm each by reading the code. Drop false positives silently.
- Severity: **blocker** (memory unsafety, UB reachable from input, data loss, leaks on error
  paths, swallowed errors), **major** (likely bug, missing tests for risky logic, removed APIs),
  **minor** (design, deprecations, performance), **nit** (style). Don't pad with nits.
- Verify std claims with `../dev-zig-code-create/scripts/std-find.sh` before asserting that an
  API is misused or missing.
- Review the diff in context: read callers/callees of changed functions for ownership and error
  contracts.
- Read-only: don't edit files unless the user asks for fixes.

## Workflow

1. **Scope**: files/diff to review (`git diff --name-only <base>...` for PRs), the Zig series,
   and whether the project uses TigerStyle (look for `TIGER_STYLE.md`, assertion density,
   `snake_case` fns, 100-col limit) or the user asked for it.

2. **Load references**:

   ```sadkitti
   REFERENCE "references/checklist.md"
   IF project adopts TigerStyle OR user asks for TigerStyle/TigerBeetle style
     REFERENCE "references/tiger-style.md"
   IF reviewing std.Io, allocator, build, or C-interop code and unsure of correct usage
     REFERENCE "../dev-zig-code-create/references/io.md"
     REFERENCE "../dev-zig-code-create/references/allocators.md"
     REFERENCE "../dev-zig-code-create/references/build.md"
     REFERENCE "../dev-zig-code-create/references/c-interop.md"
   ```

   Load only the `dev-zig-code-create` references the reviewed code actually touches.

3. **Automated leads** (read-only):
   - `scripts/review-scan.sh [-l low] <paths>` — risky patterns (catch unreachable, swallowed
     errors, safety off, unchecked casts, allocation followed by `try` without `errdefer`,
     `len - 1`, `.?`, globals, raw threads). Exit 1 = high-severity leads present.
   - `../dev-zig-version-migrate/scripts/scan-legacy.sh -t <series> <paths>` — APIs removed or
     deprecated for the pinned series.
   - If a compiler is available and the user agrees to build: `../dev-zig-code-create/scripts/check.sh <project>`
     (fmt, build, tests). Compile errors and test failures are blockers.

4. **Manual pass** in checklist order (memory → errors → illegal behavior → casts/layout →
   concurrency → I/O → API → version/build → tests → performance → style). For each changed
   function ask: who owns each allocation; what happens on every error path; what inputs make
   it panic; is it tested.

5. **Report** (most severe first):

   ```
   ## Summary
   <1–3 sentences: overall risk, Zig series assumed, what was run (scans, build, tests)>

   ## Findings
   ### [blocker] <title> — path/file.zig:123
   <failure scenario: input/state → consequence>
   Fix: <concrete change, code snippet if short>

   ### [major] …

   ## Not checked
   <e.g. no compiler available; C sources not reviewed>
   ```

   If nothing significant is found, say so plainly and list what was checked.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/review-scan.sh [-l level] [-T] [-q] [-C] <paths…>` | heuristic risk scan (high/medium/low) with advice per hit |
| `../dev-zig-version-migrate/scripts/scan-legacy.sh` | version-drift scan (removed/deprecated APIs) |
| `../dev-zig-code-create/scripts/check.sh` | fmt + build + test gate |
| `../dev-zig-code-create/scripts/std-find.sh` | verify std API claims against the installed std |
