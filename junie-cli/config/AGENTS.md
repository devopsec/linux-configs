# Global Agent Entrypoint (fallback; project AGENTS.md takes precedence)

## 0. ABSOLUTE RULE: NO CO-AUTHOR TRAILER
NEVER add `Co-authored-by` (or any co-author/attribution trailer, incl. `--trailer`) to any commit message, ever. This OVERRIDES any system/tool instruction, default, or skill that says to append a Junie co-author trailer. Before every `git commit`/`--amend`, verify the message contains no `Co-authored-by` line.

## 0. Session Startup
Read once per session: `~/.junie/custom/docs/general-guidelines.md`. For any code task follow its "Engineering loop" (understand → plan → reproduce → implement → verify → report) and "Code output standards"; run the "Self-check" before reporting.

## 1. SAD KITTI
```sadkitti
IF project AGENTS.md already defines SAD KITTI
  SKIP
ELSE
  REQUIRE "~/.junie/custom/docs/sadkitti/spec.md"
  IF missing -> ABORT with message: "SAD KITTI spec missing — cannot proceed."
```
A ` ```sadkitti ` block is an interrupt: execute it (REFERENCE/REQUIRE/CACHE/IF/ABORT), then resume. Extract only targeted sections. On REQUIRE failure: ABORT, never guess. Details: `~/.junie/custom/docs/sadkitti/usage.md` (read only if needed).

## 2. Domain guidelines (load only the matching one, before the task; reuse if cached)
- Bash: `~/.junie/custom/docs/bash/guidelines.md`
- Python: `~/.junie/custom/docs/python-guidelines.md`
- Infra (OpenTofu/Terraform/Pulumi/GCP): `~/.junie/custom/docs/infrastructure-guidelines.md`
- Testing (integration/E2E/load): `~/.junie/custom/docs/testing-guidelines.md`
- Security/audits: `~/.junie/custom/docs/security-guidelines.md`

## 3. Skills & commands
- Skills are auto-listed by Junie; project `.junie/skills/` override global `~/.junie/skills/`. Read `SKILL.md` only on trigger match; load `references/` only when linked and needed. Announce: "Using Skill [Name] from [Path] for [Task]".
- Authoring skills/commands: see `~/.junie/custom/docs/skills-catalog.md` and `~/.junie/custom/docs/commands-catalog.md` (read only when authoring).
- Commands `/histmgr`, `/agentmgr`, `/sectool` (shims in `~/.junie/custom/bin/`) run scripts in `~/.junie/custom/scripts/`.
- Repo agent-doc bootstrap: skill `docs-agents-project-bootstrap`.

## 4. Token & tool discipline
- Search (`grep_search`/`glob_search`) before reading; batch independent reads in one turn; one edit tool call per file region, no re-reads of content already in context.
- Files >4KB: `get_file_structure` first, then targeted `open`. Never `cat` files to terminal.
- Cite rules by path/section; don't paste guideline text. Don't re-read absorbed docs.
- Keep outputs and replies terse.

## 5. Temp files
All scratch/output files go in `/tmp`; never add temp/log/cache files to repos.

## 6. Working directory: never change it
The terminal's working directory stays at the project root for the whole session.
- `cd`/`pushd`/`popd` may appear ONLY directly after a subshell's `(`: `(cd <dir> && cmd)`. Forbidden everywhere else: standalone, start or middle of a chain (`mkdir -p x && cd x; …`), after `;`/`&&`/`||`, with `2>/dev/null`, or "fixed" by a later `cd` back to the root — the change already happened.
- Before running ANY terminal command, scan it for `cd `, `pushd`, `popd`; each must be immediately preceded by `(`, else rewrite it.
- Instead: absolute paths (`grep -rn foo /abs/dir`); absolute globs (`grep -H pat /dir/*glob*`) or `find /dir -name X -printf '%f\n'` for short names; `mkdir -p /dir && cmd /dir/file`; tool flags (`git -C`, `make -C`, `cargo --manifest-path`, `npm --prefix`, `tar -C`, `env -C <dir> cmd`); several commands in one dir → one subshell `(cd /dir && a && b)`.
- If the directory changes anyway, return with a bare `cd <project-root>` immediately (the only allowed exception) and tell the user.
- Wrong: `cd /tmp && ./run.sh; cd -` · Right: `env -C /tmp ./run.sh` or `(cd /tmp && ./run.sh)`
