# Replacing `gh` with `forge` (primary) or `gcli`

`gh` is not used in this environment. Translate to **forge** for anything scripted or
mutating (flags only, JSON output, `forge api` for gaps); use **gcli** for human-readable
summaries, GitLab pipeline job logs, threaded review discussions, Bugzilla, or when forge
lacks a feature (see `../../vcs-gcli-any-manage/SKILL.md`). Verified against forge 0.10.1 and
gcli 2.13.0.

Paradigm differences:
- `gh … --json f -q expr` → `forge … -o json | jq expr`. Field names differ (normalized
  schema, see `commands.md`): `nameWithOwner` → `full_name`, `headRefName` → `.head.ref`,
  `isDraft` → `.draft`, `milestone.title` stays.
- `gh api … --jq/--paginate/-F/--input` → `forge api … | jq`, `scripts/api-pages.sh`;
  `forge api -f` sends strings only.
- gcli syntax is `gcli <subcommand> [forge-path] [-o owner -r repo] -i <id> <actions…>`;
  forge-path shorthands: `gh:owner/repo`, `gl:owner/repo`, `cb:owner/repo` (Codeberg),
  `<account>:owner/repo`. gcli opens `$EDITOR` for bodies — run those via
  `../../vcs-gcli-any-manage/scripts/gcli-msg.sh <file> gcli … -y`.

## Mapping

| `gh` | `forge` | `gcli` |
|---|---|---|
| `gh auth status` | `forge auth status`, `scripts/forge-ctx.sh` | `ls ~/.config/gcli/config` (accounts; no status cmd) |
| `gh auth login` | user runs `forge auth login --domain H --token-cmd '…'` | user edits `~/.config/gcli/config` (`token=`; chmod 600) |
| `gh repo view --json nameWithOwner -q .nameWithOwner` | `forge repo view -o json \| jq -r .full_name` | — |
| `gh repo clone o/r` | `forge repo clone o/r` | `git clone` |
| `gh repo fork` | `forge repo fork` | `gcli forks create` |
| `gh pr list [--state all]` | `forge pr list [-s all] [-L n]` | `gcli pulls [-a] [-n n]` |
| `gh pr list --author A --label L` | `forge pr list -A A -l L` | `gcli pulls -A A -L L` |
| `gh pr view [N]` | `forge pr view [N] [-c]` | `gcli pulls -i N all comments` |
| `gh pr view --json number -q .number` | `forge pr view -o json \| jq -r .number` | — |
| `gh pr view --json milestone` | `forge pr view N -o json \| jq '.milestone.title // "none"'` | `gcli pulls -i N status` |
| `gh pr diff N` | `forge pr diff N` | `gcli pulls -i N diff` |
| `gh pr checkout N` | `forge pr checkout N` | `gcli pulls -i N checkout` |
| `gh pr create --title T --body B --base X --head Y --label L --milestone M --reviewer R [--draft]` | `forge pr create -t T -b B -B X -H Y -l L -m <number> -r R [-d] [--push]` | `gcli-msg.sh body.md gcli pulls create -t X -f owner:Y -l L [-d] -y "T"` (milestone/reviewers: follow-up actions) |
| `gh pr edit N --title/--body` | `forge pr edit N -t …/-b …` | `gcli pulls -i N title "…"` |
| `gh pr edit N --add-label L` | `forge pr edit N -l <existing…>,L` (replaces set) | `gcli pulls -i N labels add L` |
| `gh pr edit N --milestone M` | `forge issue edit N -m <number>` (GitHub/Gitea) | `gcli pulls -i N milestone <id>` |
| `gh pr edit N --add-reviewer R` | `forge pr reviewer request N R` | — |
| `gh pr comment N --body B` | `forge pr comment N -b B` | `gcli-msg.sh msg.md gcli comment -p N -y` |
| `gh pr review N --approve --body B` | `forge pr review approve N -b B` | `gcli pulls -i N approve -y -T msg.md` |
| `gh pr review N --request-changes --body B` | `forge pr review reject N -b B` | interactive `review` action only |
| `gh pr review N --comment --body B` | `forge api -X POST 'repos/{owner}/{repo}/pulls/N/reviews' -f event=COMMENT -f body=B` | — |
| `gh pr checks N` | `forge ci list -b <head>` + check-runs API (`api-recipes.md`) | `gcli pulls -i N ci` |
| `gh pr merge N --merge --delete-branch --subject S --body B` | `forge pr merge N -m merge -d --commit-title S --commit-message B` | `gcli pulls -i N merge` (deletes source branch by default) |
| `gh pr merge N --squash` / `--rebase` | `-m squash` / `-m rebase` | `merge -s` / not supported |
| `gh pr close N` / `gh pr reopen N` | `forge pr close N` / `forge pr reopen N` | `gcli pulls -i N close` / `reopen` |
| `gh pr ready N` | — (GitHub GraphQL; web UI) | — |
| `gh issue list --assignee @me` | `forge issue list -a "$(forge api user \| jq -r .login)"` | `gcli issues -S <login>` |
| `gh issue view N --comments` | `forge issue view N -c` | `gcli issues -i N all comments` |
| `gh issue create -t T -b B -l L` | `forge issue create -t T -b B -l L [-m M] [-a U]` | `gcli-msg.sh body.md gcli issues create -y "T"` then `gcli issues -i N labels add L` |
| `gh issue comment N -b B` | `forge issue comment N -b B` | `gcli-msg.sh msg.md gcli comment -i N -y` |
| `gh issue close/reopen N` | `forge issue close/reopen N` | `gcli issues -i N close/reopen` |
| `gh label list` | `forge label list [-o json]` | `gcli labels` |
| `gh label create L --color C --description D` | `forge label create L -c C -d D` | `gcli labels create -n L -c C -d D` |
| `gh api repos/O/R/milestones` | `forge milestone list -s open -o json` | `gcli milestones` |
| `gh api …/milestones/M -X PATCH -f state=closed` | `forge milestone close M` | — (no close action) |
| `gh run list [--branch B] [--workflow W]` | `forge ci list [-b B] [--workflow W]` | `gcli pipelines` (GitLab) |
| `gh run view ID` | `forge ci view ID` | `gcli pipelines -p ID all` (GitLab) |
| `gh run view ID --log-failed` | `forge ci view ID` → failed job IDs → `forge ci log JOB` | `gcli pipelines -j JOB log` (GitLab) |
| `gh run rerun ID` / `gh run cancel ID` | `forge ci retry ID` / `forge ci cancel ID` | `gcli pipelines -j JOB retry/cancel` |
| `gh run watch ID` | poll `forge ci view ID -o json \| jq -r .status` | `gcli pipelines -p ID monitor` (GitLab, TTY) |
| `gh workflow run W -f k=v --ref B` | `forge ci run W -b B -F k=v` | — |
| `gh release list/view/create/upload/download` | `forge release list/view/create/upload/download` | `gcli releases [create -t tag -n name …]` |
| `gh secret list/set` | `forge secret list` / user runs `forge secret set` | — |
| `gh search repos Q` | `forge search repos Q` | — |
| `gh browse [N]` | `forge browse [N] [-n]` | `gcli pulls -i N open` |
| `gh status` / notifications | `forge notification list [--unread]` | `gcli status` |
| `gh api ENDPOINT` | `forge api ENDPOINT` | `gcli api [-a] /ENDPOINT` (GET only) |

## Translating scripts

```bash
# gh
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PR=$(gh pr view --json number -q .number)
gh api "repos/$REPO/pulls/$PR/comments?per_page=100" --jq '.[].id'

# forge — no REPO variable needed: {owner}/{repo} are substituted
PR=$(forge pr view -o json | jq -r .number)
scripts/api-pages.sh "repos/{owner}/{repo}/pulls/$PR/comments" | jq '.[].id'
```

- `gh` flags with `@me` → resolve the login first (`forge api user | jq -r .login`).
- `gh … --input - <<<'{"in_reply_to": 123, …}'` (typed JSON) has no forge equivalent; use
  string-only endpoints (`…/comments/123/replies`) or native commands.
- Shell aliases are not a substitute in skills/docs — write the forge command explicitly.
