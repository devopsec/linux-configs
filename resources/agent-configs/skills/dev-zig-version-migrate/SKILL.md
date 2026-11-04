---
name: dev-zig-version-migrate
description: "Port Zig code, build.zig, and build.zig.zon between Zig releases (0.13 → 0.14 → 0.15 → 0.16 → 0.17 → 0.18-dev master): find removed/deprecated APIs, apply the replacements, and verify with the target compiler. Use when asked to upgrade/update/port/migrate a Zig project or dependency to a newer Zig, fix errors that appeared after a Zig upgrade, check which Zig version code targets, or explain what changed between Zig versions (Writergate std.Io, unmanaged ArrayList, std.Io interface/juicy main, @Type split, @cImport removal, @backingInt, SafeAllocator, build configurer/maker)."
---

# Zig version migration

Each Zig minor release breaks std, the build API, and sometimes syntax. Port **one series at a
time** (0.14 → 0.15 → 0.16 → 0.17); each step compiles before the next. Never mix APIs from
different series in one file.

## Ground rules

- Confirm the source and target series first; ask if the user did not state the target.
  Default target = latest stable (0.17 as of 2026-11); 0.18-dev only on request.
- The target compiler is the final judge. Use `scripts/scan-legacy.sh` to plan, the compiler to
  find what grep cannot, and the target's std source (`dev-zig-code-create/scripts/std-find.sh`
  with `ZIG=<target zig>`) to confirm replacements.
- Mechanical edits first (`zig fmt` auto-upgrades some syntax), semantic edits second, behavior
  changes last — and call those out in the report (`@bitCast` endianness, `containsAtLeastScalar`
  argument swap, `@hasDecl` visibility, `{}` vs `{f}` formatting).
- Update dependencies to versions that support the target series; never hand-edit a package
  `.hash`. Upstream for Zig and official packages is **Codeberg** (`codeberg.org/ziglang/…`).
- Keep the diff reviewable: no refactors beyond what the port needs.

## Workflow

1. **Establish versions.**
   - Source: `build.zig.zon` `.minimum_zig_version`, CI config, `.zigversion`/mise/asdf pins,
     or API fingerprints (run `scripts/scan-legacy.sh -q -t 0.17 <src>`: the lowest series with
     many "removed" hits is roughly where the code stops compiling).
   - Target compiler: `../dev-zig-code-create/scripts/zig-env.sh`; side-by-side compilers via
     `ZIG=/path/to/zig-0.16/zig`.

2. **Load the notes for each step** between source and target:

   ```sadkitti
   IF source < 0.14 AND target >= 0.14
     REFERENCE "references/0.14.md"
   IF source < 0.15 AND target >= 0.15
     REFERENCE "references/0.15.md"
   IF source < 0.16 AND target >= 0.16
     REFERENCE "references/0.16.md"
   IF source < 0.17 AND target >= 0.17
     REFERENCE "references/0.17.md"
   IF target is 0.18-dev / master
     REFERENCE "references/0.18-dev.md"
   IF writing new code during the port
     REFERENCE "../dev-zig-code-create/SKILL.md"
   ```

3. **Inventory.** `scripts/scan-legacy.sh -f <source> -t <next> <paths>` → findings grouped by
   version and kind (`removed` must change, `deprecated` should change, `review` needs a human
   look). Save the summary for the report.

4. **Port one series step** (repeat per step):
   1. `build.zig.zon`: bump `.minimum_zig_version`; fix `.name`/`.fingerprint` (0.14); update
      dependency URLs/hashes with `zig fetch --save` to versions supporting the step.
   2. `build.zig`: per the step's table (root_module 0.15, Module methods 0.16,
      `addPassthruArgs`/`translate_c` 0.17). Build files fail first and block everything else.
   3. `zig fmt` the tree with the target compiler (auto-upgrades e.g. `@intFromEnum`).
   4. Source: work the scan findings file by file, then iterate on compiler errors —
      `zig build -freference-trace 2>&1 | head -60`, fix the first error, rebuild.
   5. `zig build test` on the step's compiler. Fix leaks/behavior changes before moving on.

5. **Verify** with the final target: `../dev-zig-code-create/scripts/check.sh <project>`;
   re-run `scripts/scan-legacy.sh -f <target-1> -t <target> -k removed` → expect zero
   (remaining hits must be explained false positives).

6. **Report**: source → target, files changed, scan summary before/after, behavior changes that
   compile silently, deprecated APIs intentionally left, tests run (or why not).

## Scripts

| Script | Purpose |
|---|---|
| `scripts/scan-legacy.sh [-t series] [-f series] [-k kinds] [-q] [-C] <paths…>` | grep-based inventory of ~80 removed/deprecated patterns (0.14–0.17) with the fix per hit |

Coverage gaps the scanner cannot see: semantic changes (`@bitCast` on arrays, precedence in
0.18-dev, `@hasDecl` visibility), APIs reached through namespace aliases (`const time = std.time;
time.sleep(n)` — only the alias line is flagged, if at all), and method calls on values whose type is not visible on the line (e.g.
`file.close()` → `close(io)` is flagged only as `review`). The compiler catches all of these.
