---
name: vcs-gcli-any-manage
description: "Operate GitHub, GitLab, Gitea/Forgejo/Codeberg, and Bugzilla from the command line with herrhotzenplotz/gcli (`gcli`): list and inspect issues and pull/merge requests (status, op, commits, diff, CI checks, comments, threaded review discussions), GitLab pipelines and job logs/artifacts, labels, milestones, releases, forks, notifications, Bugzilla bugs and attachments, and non-interactive comments/PR/issue creation via a message-file helper. Use when the user asks for gcli, when Bugzilla or GitLab pipeline job logs are involved, when a readable PR/issue summary is wanted, or when translating gh commands to gcli. For scripted or JSON-driven forge work prefer vcs-forge-any-manage (forge)."
---

# gcli (herrhotzenplotz/gcli)

`gcli` (C, BSD-2-Clause) talks to GitHub, GitLab, Gitea/Forgejo, and Bugzilla. Output is
human-oriented tables and summaries (no JSON except `gcli api`); message bodies are written
in `$EDITOR`. Verified against gcli 2.13.0 (`man gcli`, `man gcli-<subcommand>`, `man 5 gcli`).

## Ground rules (read first)

- **No confirmations off a TTY.** gcli answers "yes" to every confirmation whenever stdin is
  not a terminal — which is always the case for agents. Creates, comments, merges, closes,
  and deletes execute immediately, and there is no dry run. Your approval gate is the only
  safety: show the user the exact command, target repo, and message, get approval, then run.
- **Explicit target for every write.** Put `-o owner -r repo` *after* the subcommand verb
  (`gcli pulls create -o O -r R …`, `gcli comment -o O -r R -p N`). Options placed before
  `create` turn it into a search term, and a forge-path before `create` was ignored in testing
  (the PR target fell back to the current checkout's remote). Forge-paths
  (`gh:o/r`, `gl:o/r`, `cb:o/r`, `<account>:o/r`) are fine for listing/reading.
- **Bodies via file, never the editor.** Write the body to a file and run
  `scripts/gcli-msg.sh <file> gcli … -y`. Lines starting with `!` are stripped by gcli (the
  helper refuses them). `approve` takes `-T <file> -y` directly.
- **Merging deletes the source branch by default** (`gcli pulls -i N merge`); `merge -D`
  keeps it, `merge -s` squashes, and the two cannot be combined in one call. No rebase
  merge — use forge (`vcs-forge-any-manage`) for rebase or full control.
- Global overrides go **before** the subcommand: `gcli -t github|gitlab|gitea|bugzilla`,
  `-a <account>`, `-r <remote>` (git remote to infer from — not the repo), `--no-markdown`,
  `--no-spinner`. Env: `GCLI_ACCOUNT`, `GCLI_NOSPINNER=1`, `NO_COLOR=1`,
  `GCLI_RENDER_MARKDOWN=0`.
- **Credentials** live in `~/.config/gcli/config` as plaintext `token=` per account (no env
  token, no token command). Don't read or print that file; if an account is missing, ask the
  user to add it (`man 5 gcli`) and `chmod 600` it. Unauthenticated public reads work
  (rate-limited).
- Never commit from this skill; no force pushes.

## Workflow

1. **Context**: `git remote -v`, current branch; for a non-default forge pick `-t`/`-a`, for
   another repo `-o/-r` or a forge-path. Reads need no confirmation.
2. **Load references** as needed:

   ```sadkitti
   IF need exact syntax for a subcommand or action
     REFERENCE "references/commands.md"
   IF translating gh commands, or the task needs JSON/flags-only automation
     REFERENCE "../vcs-forge-any-manage/references/gh-migration.md"
   ```

3. **Read** (`gcli pulls -i N all comments`, `gcli issues -i N all`), **propose**, get
   **approval**, **execute** (writes run immediately), **verify** by reading back.

## Everyday commands

| Task | Command |
|---|---|
| Open PRs / issues | `gcli pulls [-n 50]` · `gcli issues [-a] [-L label] [-S assignee]` · `gcli pulls gh:owner/repo` |
| PR summary, comments, diff, checks | `gcli pulls -i N all comments` · `gcli pulls -i N diff` · `gcli pulls -i N ci` |
| Review threads / reviews (GitHub) | `gcli pulls -i N discussions` · `gcli pulls -i N reviews` |
| Checkout PR | `gcli pulls -i N checkout` |
| Comment | `scripts/gcli-msg.sh /tmp/c.md gcli comment -o O -r R -p N -y` (`-i N` for issues, `-R ID` to reply) |
| Create PR | `scripts/gcli-msg.sh /tmp/body.md gcli pulls create -o O -r R -t develop -f O:feature/x -l docs [-d] -y "feat(x): …"` |
| Create issue | `scripts/gcli-msg.sh /tmp/body.md gcli issues create -o O -r R -y "title"` |
| Approve | `gcli pulls -o O -r R -i N approve -y -T /tmp/approval.md` |
| Labels / milestone / title | `gcli pulls -i N labels add bug remove wip` · `gcli pulls -i N milestone 3` · `gcli pulls -i N title "…"` |
| Close / merge | `gcli pulls -i N close` · `gcli pulls -i N merge [-s \| -D]` (deletes branch unless `-D`) |
| GitLab pipelines | `gcli pipelines` · `gcli pipelines -p ID jobs` · `gcli pipelines -j JOB log` · `… retry` · `… artifacts -o out.zip` |
| Releases | `gcli releases [-l]` · `scripts/gcli-msg.sh notes.md gcli releases create -o O -r R -t v1.2.0 -n "v1.2.0" [-d] [-p] [-a file] -y` |
| Bugzilla | `gcli -t bugzilla issues "<quicksearch>"` · `gcli -t bugzilla issues -i ID all comments` · `gcli -t bugzilla attachments …` |
| Raw API (GET only) | `gcli api [-a] /repos/O/R/pulls/N/comments \| jq …` |

## Scripts

| Script | Purpose |
|---|---|
| `scripts/gcli-msg.sh <message-file> gcli <args…>` | run an editor-driven gcli command non-interactively with the prepared body; refuses `!` lines and stale `./gcli_message` |
