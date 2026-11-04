# Claude specifics — vcs-gcli-any-manage

- The Bash tool has no TTY, so gcli auto-confirms everything: each gcli write publishes
  immediately. Show the exact command, resolved `-o/-r` target, and body, and get explicit
  approval for that specific call before running it.
- Create message files with the Write tool under `/tmp`, then run
  `scripts/gcli-msg.sh /tmp/msg.md gcli … -y`. Never invoke a gcli command that opens an editor
  without the helper (it would block the shell).
- Prefer forge (`vcs-forge-any-manage`) when you need JSON, merges that keep the branch,
  milestone closing, or neutral reviews; use gcli for readable summaries, GitLab job logs,
  review discussions, and Bugzilla.
- Keep the Bash working directory at the project root; target other repos with `-o/-r` or a
  forge-path instead of `cd`.
- Never read or echo `~/.config/gcli/config`; ask the user to add accounts/tokens themselves.
