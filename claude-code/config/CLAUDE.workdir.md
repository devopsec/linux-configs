## 6. Working directory: never change it
The Bash working directory must stay at the project root for the whole session. Each time it changes, the sandbox creates an empty `.claude/.cc-writes/` folder in the new directory, and these pile up across repos.

Rules:
1. Do not run `cd`, `pushd` or `popd` as a standalone command or at the start of a command chain. This includes `cd dir && cmd` and `cd dir; cmd`.
2. Refer to files by absolute path: `ls /abs/path`, `grep -rn foo /abs/path`.
3. Use a tool's own directory flag when it has one: `git -C <dir>`, `make -C <dir>`, `just --justfile <dir>/justfile --working-directory <dir>`, `cargo --manifest-path <dir>/Cargo.toml`, `npm --prefix <dir>`, `tar -C <dir>`.
4. If a command only works from inside a directory, wrap it in a subshell: `(cd <dir> && cmd)`. The parentheses are required; the `cd` stays inside the subshell.
5. If the working directory changes anyway (an "Environment update" note says it changed), return to the project root right away with a bare `cd <project-root>` (the one allowed exception) and tell the user it happened.

Examples:
- Wrong: `cd ~/Projects/foo && cargo build`
- Right: `cargo build --manifest-path ~/Projects/foo/Cargo.toml`
- Right: `(cd ~/Projects/foo && just run)`
