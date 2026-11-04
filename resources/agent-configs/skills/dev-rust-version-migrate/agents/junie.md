# Junie specifics — dev-rust-version-migrate

- Execute the SKILL.md `sadkitti` routing block literally; load only the references selected
  for the upgrade the user asked for.
- Run `cargo fix --edition` and builds with the terminal tool and an extended timeout.
- Ask inline (numbered list) to confirm: target edition/MSRV, whether to raise `rust-version`
  of a published crate, installing a toolchain (`rustup toolchain install`), and broad
  `cargo update` runs.
- Edition, toolchain, and dependency upgrades are separate steps; report after each.
- No commits; the user reviews and submits each step.
