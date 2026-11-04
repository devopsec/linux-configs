# gcli command reference (gcli 2.13.0)

Condensed from the installed man pages — `man gcli-<subcommand>` has the full text. Shape:

```
gcli [overrides] <subcommand> [forge-path] [options] [-i ID] [actions…]
```

- **Overrides** (before the subcommand): `-t github|gitlab|gitea|bugzilla`, `-a account`,
  `-r remote` (git remote used for inference), `-c` (force colour), `--no-spinner`,
  `--no-markdown`, `-q`, `-v` (prints requests to stderr — useful to see the target).
- **Common options**: `-o owner -r repo` (always together), `-n N` (count, `-1` = all
  pages, beware rate limits), `-a` (include closed), `-s` (reverse order), `-y` (assume
  yes — implied off-TTY anyway), `-i ID` (item to act on).
- **Forge paths**: `gh:o/r` (GitHub), `gl:o/r` (GitLab), `cb:o/r` (Codeberg), `acct:o/r`,
  `acct`. Placed right after the subcommand; use for reads. For writes use `-o/-r` after the
  verb (`create`) or with `-i`.
- Several actions can be chained: `gcli pulls -i 12 status commits ci comments`.
- Abbreviations work: `pu` = `pulls`, `pr` = `pulls`.

## pulls (`gcli-pulls(1)`, `gcli-pulls-review(1)`)

```
gcli pulls [path] [-a] [-A author] [-L label] [-M milestone] [-s] [-n N] [-o O -r R] [search…]
gcli pulls [path] -i N [-o O -r R] actions…
gcli pulls create [-o O -r R] [-t base] [-f owner:branch] [-l label]… [-R reviewer]… [-d] [-a] [-T template] [-y] "title"
```

| Action | Effect |
|---|---|
| `all` | `status op commits ci` |
| `status` / `op` / `commits` / `comments` (`notes`) | metadata / description / commits / comments |
| `ci` | GitHub check runs or GitLab pipelines of the PR |
| `diff` | unified diff (pipe to `git apply`) |
| `checkout` | checkout head branch (needs a clone of the target repo) |
| `reviews` / `discussions` | list reviews / threaded review discussions (GitHub only) |
| `approve [-y] [-T file]` / `unapprove` | approve with body from file; revoke |
| `review` | interactive annotated-diff review — **experimental** (`GCLI_ENABLE_EXPERIMENTAL=yes`), editor + prompts: not usable by agents |
| `labels add L remove L …` | change labels (repeatable) |
| `milestone ID` / `milestone -d` | set / clear milestone |
| `title "new"` / `assign user` | rename / assign |
| `close` / `reopen` | state changes |
| `merge [-s \| -D]` | merge commit (default); `-s` squash; `-D` keep the source branch. **Source branch deleted by default** unless `-D` or `.gcli` `pr.inhibit-delete-source-branch=yes`. Only the first flag is parsed, so squash + keep-branch needs the `.gcli` setting (the man page wrongly says `-D` deletes) |
| `open` | open in browser (`xdg-open`) |

`create` opens the editor for the body (use `scripts/gcli-msg.sh`), derives `-f` from the
current branch when omitted, and takes the base from `.gcli` `pr.base` when `-t` is omitted.
On failure it saves the body to `./gcli_message`. `-a` here means automerge, not "all".

## issues (`gcli-issues(1)`)

```
gcli issues [path] [-n N] [-a] [-s] [-A author] [-L label] [-M milestone] [-S assignee] [-o O -r R] [search…]
gcli issues [path] -i N [-o O -r R] actions…
gcli issues create [-o O -r R] [-T template] [-y] "title"
```

Actions: `all`, `status`, `op`, `comments`/`notes`, `close`, `reopen`, `assign user`,
`labels add L remove L`, `milestone ID` / `milestone -d`, `title "…"`, `due YYYY-MM-DD`,
`edit` (editor — avoid), `open`, `attachments` (Bugzilla).

## comment (`gcli-comment(1)`)

```
gcli comment [path] [-o O -r R] (-i issue | -p PR) [-R comment-id] [-y]
```

Always opens the editor → `scripts/gcli-msg.sh msg.md gcli comment -o O -r R -p N -y`.
`-R ID` quotes the replied-to comment into the template; the helper replaces the whole
template with your file, so include any quote yourself.

## labels, milestones, releases, forks, repos

```
gcli labels [path] [-o O -r R]
gcli labels create [-o O -r R] -n name -d description -c RRGGBB
gcli labels [-o O -r R] -i name  status | name NEW | description "…" | colour RRGGBB | delete

gcli milestones [path] [-o O -r R]
gcli milestones [path] [-o O -r R] -i ID  all | status | issues | delete | open
gcli milestones create [-o O -r R] -t title [-d description]          # no close action → use forge

gcli releases [path] [-l] [-s] [-n N] [-o O -r R]
gcli releases create [-o O -r R] -t tag [-n name] [-c commitish] [-a asset]… [-d] [-p] [-T notes.md] [-y]   # editor for notes
gcli releases delete [-o O -r R] [-y] RELEASE-ID

gcli forks [path] [-o O -r R] [-n N]          # list
gcli forks create [-o O -r R] [-i target-owner]
gcli repos …                                   # list/create/delete own repos — see gcli-repos(1)
```

## pipelines (`gcli-pipelines(1)`) — GitLab CI

```
gcli pipelines [path] [-n N] [-o O -r R] [-a]
gcli pipelines -p PIPELINE [-o O -r R]  all | status | jobs | children | open | monitor [-d secs]
gcli pipelines -j JOB [-o O -r R]       log | status | cancel | retry | artifacts [-o file.zip]
```

`monitor` needs an xterm-compatible TTY (not for agents). For GitHub Actions use
`gcli pulls -i N ci` or forge (`forge ci …`).

## status, api, config, Bugzilla

```
gcli status [-l] [-n N]         # notifications / TODOs;  gcli status -m ID  marks one read
gcli api [-a] /path             # GET only, raw JSON; -a follows pagination; path from API root
gcli config …                   # e.g. SSH key management — see gcli-config(1)

gcli -t bugzilla issues "product:Ports component:Individual …"     # Bugzilla quicksearch
gcli -t bugzilla issues -i BUG all comments attachments
gcli attachments -i ATTACHMENT actions…
gcli attachments create -i BUG -f file|- -s "summary" [-p] [-c "comment"] [-C content-type] [-F name]
```

## Configuration (`gcli(5)`)

`~/.config/gcli/config` (honors `XDG_CONFIG_HOME`):

```
defaults {
    editor=/usr/bin/vim
    github-default-account=me-gh
    disable-spinner=yes
    render-markdown=no
}
me-gh {
    forge-type=github
    account=me
    token=<user adds this — never written by the agent>
    api-base=https://api.github.com      # change for self-hosted
}
```

Repo-local `.gcli` (committed): `pr.base=develop`, `pr.upstream=owner/repo`,
`pr.inhibit-delete-source-branch=yes`, `forge-type=gitea`. Suggest
`pr.inhibit-delete-source-branch=yes` for repos where merged branches must stay.
