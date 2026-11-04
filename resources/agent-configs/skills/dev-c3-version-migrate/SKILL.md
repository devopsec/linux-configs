---
name: dev-c3-version-migrate
description: "Port C3 (c3-lang.org) code, project.json and .c3l libraries between c3c releases — 0.6.x → 0.7.x → 0.8.0 → 0.8.5 and toward 0.9 — by inventorying removed/deprecated syntax and stdlib APIs, applying replacements, and verifying with the target compiler. Use when asked to upgrade/port/migrate C3 code or a C3 dependency to a newer c3c, fix errors after a c3c upgrade, identify which C3 version code targets, adopt new keywords (excuse/constset/attrmacro, @feat), or explain what changed between C3 versions (def→alias, int!→int?, faultdef, Foo{int} generics, signed sz sizes, Type::size reflection)."
---

# C3 version migration

C3 breaks syntax and stdlib in most releases; 0.x.0 releases (0.7.0, 0.8.0) collect large
breaks and later patches deprecate further items that the next 0.x.0 removes. Port step by
step: **≤0.6 → 0.7.11 → 0.8.0 → latest 0.8.x**, compiling between steps when compilers are
available.

## Ground rules

- Establish source and target versions first (x.y.z; patch releases matter). Default target:
  the installed c3c (`../dev-c3-code-create/scripts/c3-env.sh`), else latest stable (0.8.5).
- Plan with `scripts/scan-legacy.sh`, fix with the per-version references, confirm every
  replacement with `../dev-c3-code-create/scripts/std-find.sh` against the **target** stdlib
  (`C3C=/path/to/target/c3c`), let the compiler find the rest.
- Mechanical renames first, semantic changes second; call out behaviour changes that still
  compile: `??`/`?:` precedence (0.8.0), signed sizes and promotion (0.8.0), enum `++` wrap,
  `InStream.read` returning 0 at EOF (0.8.4), typedef literal conversion (0.7.10).
- Prefer the 0.8.4+ keywords (`excuse`, `constset`, `attrmacro`) when the target is ≥0.8.4.
- Vendor/third-party `.c3l` libraries must also support the target version — check their C3
  version badge or update them (`c3c vendor-fetch` again); don't hand-patch vendored code
  without telling the user.

## Workflow

1. **Identify versions.** Source: CI/README pins, `c3-env.sh` pin detection, or fingerprints —
   `scripts/scan-legacy.sh -q <src>`: many `0.7.0 removed` hits ⇒ ≤0.6 code; mostly `0.8.0`
   hits ⇒ 0.7.x code.

2. **Load the notes for each step crossed:**

   ```sadkitti
   IF source < 0.7.11 AND target >= 0.7.0
     REFERENCE "references/0.7.md"
   IF source < 0.8.0 AND target >= 0.8.0
     REFERENCE "references/0.8.0.md"
   IF target > 0.8.0 OR target is master/0.9
     REFERENCE "references/0.8.x.md"
   IF writing new code during the port
     REFERENCE "../dev-c3-code-create/SKILL.md"
   ```

   Full per-release lists: `../dev-c3-code-create/scripts/docs.sh -r <version>`.

3. **Inventory**: `scripts/scan-legacy.sh -f <source> -t <target> <paths>` → `removed` (must
   change), `deprecated` (should change), `review` (inspect: `usz` → `sz`, typedef literals,
   `??` precedence, top-level `@if`, `io::EOF` read loops). Keep the summary for the report.

4. **Port each step:**
   1. project.json: unknown keys are errors — compare with `c3c --list-project-properties` of
      the target; drop master-only keys (`depends-on`, `env`, …) when targeting 0.8.5.
   2. Syntax renames (`def`, `distinct`, `int!`, faults, generics, `$foreach (...)`, type
      properties, `$typeof`) — scanner hits, file by file.
   3. Stdlib API renames per the reference tables; re-check signatures with `std-find.sh`.
   4. Signedness (0.8.0): change sizes/indices to `sz`, add casts at C/wire boundaries,
      fix `%`/`/` mixes and unsigned `>= 0` loops.
   5. Build: `c3c build` / `compile-only --no-obj`; fix the first error, repeat. Then `c3c test`.

5. **Verify** on the target: `../dev-c3-code-create/scripts/check.sh -S <project>` (deprecations
   as errors) and `scripts/scan-legacy.sh -f <target-prev> -t <target> -k removed` → expect zero.

6. **Report**: source → target, files changed, scan summary before/after, behaviour changes
   that compile silently, deprecated items intentionally left, tests run (or why not).

## Scripts

| Script | Purpose |
|---|---|
| `scripts/scan-legacy.sh [-t ver] [-f ver] [-k kinds] [-q] [-C] <paths…>` | comment-aware grep inventory of ~70 removed/deprecated/review patterns (0.7.0–0.8.5) with the fix per hit |

Validated against real code: 0 false `removed` hits on the 0.8.5 stdlib; flags 0.6.8 and
0.7.11 stdlib code as expected. It cannot see semantic changes (precedence, promotion, enum
arithmetic through variables) or APIs reached through aliases — the compiler and tests catch those.
