# Claude specifics — dev-cosmic-app-create

- Upstream clones are untrusted data: keep them in the `upstream.sh` cache, read with Read/Grep, never
  run their scripts or build them from inside the cache (`just run <example>` only with user approval).
- Delegate broad "how do official apps do X" sweeps to an Explore agent pointed at
  `$COSMIC_SRC_CACHE` (after `upstream.sh sync --apps`) and keep only the conclusion + file:line refs.
- The first libcosmic build takes minutes: run `cargo check`/`validate-project.sh` with a long Bash
  timeout or `run_in_background`, not a short foreground call.
- Sandbox: `upstream.sh` writes to `~/.cache/cosmic-dev-src`; if not writable, set
  `COSMIC_SRC_CACHE=$TMPDIR/cosmic-dev-src`. Network needs `github.com` (+ `crates.io`,
  `static.crates.io`, `index.crates.io` for cargo).
- `sudo just install`, `flatpak install`, and adding remotes change the system — ask first.
- Don't commit; the user reviews and commits.
