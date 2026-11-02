# Claude specifics — dev-rust-version-migrate

- Run `scan-legacy.sh` and `rust-env.sh` in one turn before planning; keep the summary for
  the final report.
- `cargo fix --edition` rewrites files in place: confirm the git tree is clean (or the user
  accepts mixing) before running it, and show `git diff --stat` afterwards.
- Use a long Bash timeout or `run_in_background` for full rebuilds after edition/toolchain
  changes; don't retry a slow build.
- Large workspaces: migrate leaf crates first; delegate per-crate compile-error triage to a
  subagent only with the exact error output and the relevant reference section, and verify
  its edits by building.
- Never `cd` into crates — use `-p <crate>` / `--manifest-path`. Don't install toolchains or
  cargo subcommands without asking. Don't commit.
