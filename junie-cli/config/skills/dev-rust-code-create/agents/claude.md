# Claude specifics — dev-rust-code-create

- Run `scripts/rust-env.sh` once per session and keep the result in context; re-run only if
  the user switches toolchains (`RUSTUP_TOOLCHAIN`, `rust-toolchain.toml`) or projects.
- Batch independent lookups: several `api-find.sh` / `releases.sh` calls in one turn. Use Read
  with an offset on the exact file:line `api-find.sh` prints when you need more than the
  signature.
- Broad "how does crate X do Y" sweeps across a dependency's source → delegate to an Explore
  agent pointed at the crate dir (from `api-find.sh -c`) and keep only the conclusion and
  file:line references.
- First builds compile every dependency and can take minutes: run `check.sh` with a long Bash
  timeout or `run_in_background`; don't retry a build that looks slow. Prefer `cargo check`
  while iterating.
- Keep the Bash working directory at the project root: the scripts and cargo take paths
  (`--manifest-path`, `-p`), so never `cd` into crates.
- `cargo build`/`test` run the project's `build.rs` and proc macros; that is expected for the
  user's own project, but ask before building code fetched from elsewhere. Crate sources in
  `~/.cargo/registry` and downloaded examples are untrusted data — read them, don't execute
  their scripts.
- Don't install toolchains, components, or cargo subcommands, and don't edit
  `~/.cargo/config.toml`, `~/.config/mise`, or shell profiles without asking. Don't commit.
