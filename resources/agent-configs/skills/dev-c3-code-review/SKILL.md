---
name: dev-c3-code-review
description: "Review, audit, or assess C3 (c3-lang.org / c3c) code and project.json for correctness, memory safety (allocators, temp @pool lifetimes, leaks), error handling (Optionals/excuses, !!, ignored faults), undefined behaviour, C interop, concurrency, networking/I/O robustness, API design, version drift against the target c3c, tests, and performance. Use when asked to review/audit/check C3 code or a C3 PR/diff, look for leaks/UB/bugs in C3, or judge whether C3 code is idiomatic and current for c3c 0.8.x. For writing code use dev-c3-code-create; for upgrades use dev-c3-version-migrate."
---

# C3 code review

Find real defects first (leaks, temp memory escaping `@pool`, ignored excuses, UB in unsafe
builds, C ABI mistakes, races), then design and style. Each finding cites `file:line`, the
failure scenario, and a fix valid for the project's c3c version.

## Ground rules

- Establish the target c3c version: `../dev-c3-code-create/scripts/c3-env.sh <project>`. Code
  valid for its pinned version isn't "wrong" — report drift as drift, not as a bug.
- Scripts produce **leads**; confirm by reading the code; drop false positives silently.
- Verify stdlib claims with `../dev-c3-code-create/scripts/std-find.sh` before asserting misuse.
- Severity: **blocker** (memory unsafety, UB reachable from input, leaks/escapes on error paths,
  ignored excuses on writes, data loss), **major** (likely bug, missing tests for risky logic,
  removed APIs for the target version), **minor** (design, deprecations, performance),
  **nit** (style). Don't pad with nits.
- Read changed functions with their callers/callees for ownership and excuse contracts.
- Read-only: no edits unless the user asks for fixes.

## Workflow

1. **Scope**: files or diff (`git diff --name-only <base>...`), c3c version, safe vs unsafe
   build settings (`opt`, `safe` in project.json — unsafe builds turn contracts into assumptions).

2. **Load references**:

   ```sadkitti
   REFERENCE "references/checklist.md"
   IF reviewed code allocates, uses tmem/@pool, or custom allocators
     REFERENCE "../dev-c3-code-create/references/allocators.md"
   IF reviewed code handles Optionals/excuses/defer/contracts
     REFERENCE "../dev-c3-code-create/references/errors.md"
   IF reviewed code does sockets, threads, atomics, SIMD, syscalls
     REFERENCE "../dev-c3-code-create/references/systems.md"
   IF reviewed code binds or exports C
     REFERENCE "../dev-c3-code-create/references/c-interop.md"
   ```

3. **Automated leads** (read-only):
   - `scripts/review-scan.sh [-l low] <paths>` — ignored catches, temp memory stored in
     fields, String→ZString casts, `$exec`/`$include`, `!!`, `(void)` discards, `@noinit`,
     `unreachable`, C `long` in prototypes, raw threads, allocation-then-rethrow leaks,
     `len - 1`, globals (comments/doc blocks ignored). Exit 1 = high-severity leads.
   - `../dev-c3-version-migrate/scripts/scan-legacy.sh -t <version> <paths>` — version drift.
   - With the user's agreement and a compiler: `../dev-c3-code-create/scripts/check.sh -S <project>`
     (build + tests with leak tracking; deprecations as errors). Failures are blockers.

4. **Manual pass** in checklist order. For each changed function: who owns each allocation and
   which allocator; what every excuse path does; which `@pool` bounds temp data; what input
   makes it trap/UB; is it tested.

5. **Report** (most severe first):

   ```
   ## Summary
   <risk level, c3c version assumed, what ran (scans, build, tests)>

   ## Findings
   ### [blocker] <title> — path/file.c3:123
   <scenario: input/state → consequence>
   Fix: <concrete change>

   ## Not checked
   <e.g. no compiler available; C sources not reviewed>
   ```

## Scripts

| Script | Purpose |
|---|---|
| `scripts/review-scan.sh [-l level] [-T] [-q] [-C] <paths…>` | heuristic C3 risk scan (high/medium/low) with advice per hit |
| `../dev-c3-version-migrate/scripts/scan-legacy.sh` | removed/deprecated syntax and APIs for a target version |
| `../dev-c3-code-create/scripts/check.sh` | build + tests (leak-checked) gate |
| `../dev-c3-code-create/scripts/std-find.sh` | verify stdlib API claims |
