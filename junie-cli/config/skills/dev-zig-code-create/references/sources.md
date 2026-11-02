# Zig sources of truth

Zig is pre-1.0: every minor release (0.14 → 0.15 → 0.16 → 0.17) breaks std and sometimes syntax.
Training data is dominated by 0.11–0.13 code. Check every API against the toolchain in use.

## Order of trust

1. **Installed std source** — `scripts/std-find.sh <name> [path-filter]` (reads `std_dir` from
   `zig env`). Signatures, doc comments, and `/// Deprecated` notes are authoritative.
2. **Local language reference** — `scripts/zig-env.sh -f langref` (release tarballs ship
   `doc/langref.html`). Covers syntax, builtins, casting, illegal behavior.
3. **`zig init` templates** — `<lib_dir>/init/{build.zig,build.zig.zon,src/main.zig,src/root.zig}`:
   canonical build script, `main` signature, test and fuzz layout for that exact version.
4. **Online docs for the matching version** (replace `0.17.0` with the series in use):
   - Language reference: <https://ziglang.org/documentation/0.17.0/>
   - Std docs: <https://ziglang.org/documentation/0.17.0/std/> (or run `zig std` for a local server)
   - Release notes: <https://ziglang.org/download/0.17.0/release-notes.html>
   - Master (unreleased, moves daily): <https://ziglang.org/documentation/master/> and
     <https://ziglang.org/documentation/master/std/>
   - Version index (stable + current master build): <https://ziglang.org/download/index.json>
   - Build system guide: <https://ziglang.org/learn/build-system/>
   - Devlog (master changes before release notes exist): <https://ziglang.org/devlog/>
5. **Upstream source & issues (Codeberg — the project left GitHub)**:
   - Compiler + std: <https://codeberg.org/ziglang/zig> (`git clone https://codeberg.org/ziglang/zig.git`)
   - C translation package (0.17+): <https://codeberg.org/ziglang/translate-c>
   - Issues/PRs: <https://codeberg.org/ziglang/zig/issues>. GitHub `ziglang/zig` links in older
     material are archived history only.
6. **Community material** — useful for orientation, never authoritative:
   - zigcc/skills (<https://github.com/zigcc/skills>): per-version notes (0.15/0.16/0.17) and a
     TigerStyle digest. Several 0.16/0.17 snippets are wrong (e.g. `Group.wait` → real name is
     `Group.await`; `Writer.fixed(...).interface` → `Writer.fixed` already *is* the interface;
     claims that `std.Io.net` only exposes vtable calls — `IpAddress.connect/listen` and
     `HostName.connect` exist).
   - nzrsky/zig-skills (<https://github.com/nzrsky/zig-skills>): large std reference set written
     against 0.16/0.17-dev. Its advice to replace `std.Thread.Mutex`/sleep/random/time with
     pthreads/libc is wrong — use `std.Io.Mutex`, `io.sleep`, `io.random`, `std.Io.Clock`.
   - rand/discover-zig (skillmd.com): gateway listing build-system / C-interop / memory /
     package / project-setup / testing topics; no version-specific API content.
   - Zig Cookbook (<https://cookbook.ziglang.cc/>), ziglings, zig.guide: check which version
     each page targets before copying.

## Version facts (as of 2026-11)

| Series | Released | Headline |
|---|---|---|
| 0.14 | 2025-03 | decl literals, labeled switch, `@branchHint`, lowercase `@typeInfo` tags, zon `fingerprint` |
| 0.15 | 2025-08 | "Writergate" `std.Io.Reader/Writer`, unmanaged `ArrayList`, `usingnamespace`/`async` removed |
| 0.16 | 2026-04 | `std.Io` interface everywhere, "juicy" `main(init: std.process.Init)`, `@Type` split, `std.net`→`std.Io.net` |
| 0.17 | 2026-10 | `@backingInt`/`@fromBackingInt`, SoA reflection, `SafeAllocator`, `@cImport` removed, build configurer/maker split |
| 0.18-dev | master | partial operator precedence (ambiguous mixes need parens), scalar `@splat`, `\u{}` code-point literals |

Per-version porting detail lives in the `dev-zig-version-migrate` skill.

## Quick lookups

```bash
scripts/zig-env.sh .                        # toolchain + project pin, warns on mismatch
scripts/std-find.sh readFileAlloc           # where/how is it declared now?
scripts/std-find.sh -d 'Mutex' Io           # with doc comments, only under Io/
scripts/std-find.sh -a 'Deprecated' heap    # what is deprecated in std.heap?
scripts/langref.sh '@backingInt'           # one langref section as plain text
scripts/langref.sh -l | grep -i slice       # list section titles
scripts/langref.sh -u master 'Precedence'   # fetch a version's langref instead of the local one
```
