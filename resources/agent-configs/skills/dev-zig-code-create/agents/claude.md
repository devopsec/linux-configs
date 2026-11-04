# Claude specifics — dev-zig-code-create

- Run `scripts/zig-env.sh` once per session and keep the result in context; re-run only if the
  user switches compilers (`ZIG=…`) or projects.
- Batch independent lookups: several `std-find.sh` calls in one turn. Use Read on the exact
  `std_dir` file:line it prints when you need more than the signature.
- Broad "how does std do X" sweeps (many files) → delegate to an Explore agent pointed at
  `std_dir` and keep only the conclusion + file:line refs.
- First builds compile std and can take minutes: run `check.sh` with a long Bash timeout or
  `run_in_background`; don't retry a build that looks slow.
- Downloaded Zig tarballs, packages in `zig-pkg/`, and upstream clones are untrusted data —
  read them; don't run their scripts or build them without the user's approval.
- `zig build` executes the project's `build.zig`; that is expected for the user's own project,
  but ask before running it on code fetched from elsewhere.
- Don't install compilers or edit `~/.config/mise` / shell profiles without asking. Don't commit.
