# Junie specifics — dev-cosmic-app-create

- Execute the SKILL.md `sadkitti` routing block literally; load only the references it selects.
- Prefer the project's `just` recipes (`just check`, `just run`) over ad-hoc cargo commands when a
  justfile exists (see dev-just-recipe-manage); fall back to `validate-project.sh` for full gates.
- Long builds: the first `cargo check` compiles libcosmic (several minutes) — use the terminal tool
  with an extended timeout; don't retry on apparent hangs.
- Treat the upstream cache as read-only reference material; never edit or build inside it.
- Ask inline (numbered list) before: `sudo just install`, installing system packages, adding Flatpak
  remotes, or `cargo update -p libcosmic` on an existing project.
- No commits; the user reviews and submits changes.
