# Junie specifics — dev-rust-code-create

- Execute the SKILL.md `sadkitti` routing block literally; load only the references it selects.
- Prefer project `just`/`mise` tasks (`just test`, `mise run lint`) when present (see
  dev-just-recipe-manage / dev-mise-task-manage); fall back to `scripts/check.sh`.
- Use the terminal tool with an extended timeout for the first `cargo build`/`clippy` (all
  dependencies compile) and for Miri.
- Search std and dependencies with `scripts/api-find.sh` instead of opening large source
  files; when you must open one, use `get_file_structure` first.
- In PyCharm/RustRover sessions, the IDE's Rust inspections complement but don't replace
  `cargo clippy`; trust the CLI result.
- Ask inline (numbered list) before: installing/upgrading toolchains, targets, or components
  (`rustup …`), installing cargo subcommands (`cargo install …`), adding dependencies
  (`cargo add`), changing `rust-version`/`edition`/`rust-toolchain.toml`, or adding `unsafe`.
- No commits; the user reviews and submits changes.
