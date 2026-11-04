# forge command reference (forge 0.10.1)

Generated from `forge <cmd> --help`; re-check with `--help` on other versions. Every command
also takes the global flags below. `s` = string, `s…` = repeatable/comma list, `n` = integer,
`val` = repeatable `KEY=VALUE`.

## Global flags

| Flag | Meaning |
|---|---|
| `-R, --repo OWNER/REPO` | target repo (also `HOST/OWNER/REPO`); default: the git remote |
| `--remote NAME` | git remote to read when `-R` is absent (default: `.forge` setting, else `origin`) |
| `--host HOST` | force host, e.g. `gitea.example.com` or `http://forgejo.local:3000` (beats `FORGE_HOST` and remote detection) |
| `--forge-type T` | `github`, `gitlab`, `gitea`, `forgejo`, `bitbucket`, `gerrit`, `tangled` |
| `-o, --output F` | `table` (default), `json`, `plain` |

## Commands

| Usage | Flags |
|---|---|
| `forge api <endpoint>` | `-f, --field val` `-H, --header val` `-i, --include` `-X, --method s` `--silent` |
| `forge auth login` | `--domain s` `--scheme s` `--token s` `--token-cmd s` `--type s` |
| `forge auth status` |  |
| `forge branch create <name>` | `--from s` |
| `forge branch delete <name>` | `-y, --yes` |
| `forge branch list` | `-L, --limit n` |
| `forge branch show-base [branch]` | `--refresh` |
| `forge browse [<number> \| <path>]` | `--actions` `-b, --branch s` `--issues` `-n, --no-browser` `--pulls` `--releases` `--settings` `--wiki` |
| `forge ci cancel <run-id>` |  |
| `forge ci list` | `-b, --branch s` `-L, --limit n` `-s, --status s` `-u, --user s` `--workflow s` |
| `forge ci log <job-id>` |  |
| `forge ci retry <run-id>` |  |
| `forge ci run [<workflow>]` | `-b, --branch s` `-F, --field val` |
| `forge ci view <run-id>` |  |
| `forge collaborator add <username>` | `-p, --permission s` |
| `forge collaborator list` | `-L, --limit n` |
| `forge collaborator remove <username>` | `-y, --yes` |
| `forge comment <number>` | `-b, --body s` |
| `forge deploy-key add` | `-k, --key s` `--read-only` `-t, --title s` |
| `forge deploy-key delete <id>` | `-y, --yes` |
| `forge deploy-key list` | `-L, --limit n` |
| `forge file cat <path>` | `--ref s` |
| `forge file ls [path]` | `--ref s` |
| `forge issue close <number>` |  |
| `forge issue comment <number>` | `-b, --body s` |
| `forge issue create` | `-a, --assignee s…` `-b, --body s` `-l, --label s…` `-m, --milestone s` `-t, --title s` |
| `forge issue delete <number>` | `-y, --yes` |
| `forge issue edit <number>` | `-a, --assignee s…` `-b, --body s` `-l, --label s…` `-m, --milestone s` `-t, --title s` |
| `forge issue list` | `-a, --assignee s` `-A, --author s` `-l, --label s…` `-L, --limit n` `--order s` `--sort s` `-s, --state s` `-w, --web` |
| `forge issue react <number>` | `--comment n` `--reaction s` |
| `forge issue reactions <number>` | `--comment n` |
| `forge issue reopen <number>` |  |
| `forge issue view <number>` | `-c, --comments` `-w, --web` |
| `forge label create [name]` | `-c, --color s` `-d, --description s` `-f, --force` `-n, --name s` |
| `forge label delete <name>` | `-y, --yes` |
| `forge label edit <name>` | `-c, --color s` `-d, --description s` `-n, --name s` |
| `forge label list` | `-L, --limit n` `-w, --web` |
| `forge milestone close <number>` |  |
| `forge milestone create` | `-d, --description s` `--due s` `-t, --title s` |
| `forge milestone delete <number>` | `-y, --yes` |
| `forge milestone edit <number>` | `-d, --description s` `--due s` `-t, --title s` |
| `forge milestone list` | `-L, --limit n` `-s, --state s` |
| `forge milestone reopen <number>` |  |
| `forge milestone view <number>` |  |
| `forge notification list` | `-L, --limit n` `--repo s` `--unread` |
| `forge notification read` | `--id s` `--repo s` |
| `forge pr checkout <number-or-url>` | `-b, --branch s` `--detach` `-f, --force` `--remote-name s` |
| `forge pr close <number>` |  |
| `forge pr comment <number>` | `-b, --body s` |
| `forge pr create` | `-a, --assignee s…` `-B, --base s` `-b, --body s` `-d, --draft` `-H, --head s` `-l, --label s…` `-m, --milestone s` `--push` `-r, --reviewer s…` `-t, --title s` |
| `forge pr diff <number>` |  |
| `forge pr edit <number>` | `-a, --assignee s…` `-B, --base s` `-b, --body s` `-l, --label s…` `-r, --reviewer s…` `-t, --title s` |
| `forge pr list` | `-A, --author s` `--base s` `--head s` `-l, --label s…` `-L, --limit n` `--order s` `--sort s` `-s, --state s` `-w, --web` |
| `forge pr merge <number>` | `--commit-message s` `--commit-title s` `-d, --delete-branch` `-m, --method s` |
| `forge pr react <number>` | `--comment n` `--reaction s` |
| `forge pr reactions <number>` | `--comment n` |
| `forge pr reopen <number>` |  |
| `forge pr review approve <number>` | `-b, --body s` |
| `forge pr review list <number>` | `-L, --limit n` |
| `forge pr review reject <number>` | `-b, --body s` |
| `forge pr reviewer remove <number> <users...>` |  |
| `forge pr reviewer request <number> <users...>` |  |
| `forge pr view [<number>]` | `-c, --comments` `-w, --web` |
| `forge rate-limit` |  |
| `forge release create` | `-b, --body s` `--draft` `--generate-notes` `--prerelease` `--tag s` `--target s` `-t, --title s` |
| `forge release delete <tag>` | `-y, --yes` |
| `forge release download <tag> <asset-name>` | `-O, --output-file s` |
| `forge release edit <tag>` | `-b, --body s` `--draft` `--prerelease` `--tag s` `--target s` `-t, --title s` |
| `forge release list` | `-L, --limit n` |
| `forge release upload <tag> <file>` |  |
| `forge release view <tag>` |  |
| `forge repo clone <OWNER/REPO> [PATH] [-- <gitflags>...]` |  |
| `forge repo contributors [OWNER/REPO]` |  |
| `forge repo create [<name>]` | `-c, --clone` `--default-branch s` `-d, --description s` `-g, --gitignore s` `--init` `--internal` `--license s` `--owner s` `--private` `--public` `--readme` |
| `forge repo delete [OWNER/REPO]` | `-y, --yes` |
| `forge repo edit [OWNER/REPO]` | `--default-branch s` `-d, --description s` `--homepage s` `--private` `--public` |
| `forge repo fork [OWNER/REPO]` | `-c, --clone` `--name s` `--owner s` |
| `forge repo forks [OWNER/REPO]` | `-L, --limit n` `--sort s` |
| `forge repo list <owner>` | `--archived` `--forks` `-L, --limit n` `--no-archived` `--no-forks` |
| `forge repo search <query>` | `-L, --limit n` `--order s` `--sort s` |
| `forge repo view [OWNER/REPO]` |  |
| `forge search repos <query>` | `-L, --limit n` `--order s` `--sort s` |
| `forge secret delete <name>` | `-y, --yes` |
| `forge secret list` | `-L, --limit n` |
| `forge secret set` | `-n, --name s` `-v, --value s` |
| `forge status list <sha>` |  |
| `forge status set <sha>` | `--context s` `--description s` `--state s` `--url s` |

Aliases: `create`/`new` (pr, issue), `list`/`ls` (pr, issue, label). `pr view`, `pr checkout`,
`branch show-base` default to the current branch when no number is given. `pr checkout` also
accepts a full PR URL and adds fork remotes automatically.

## Behavior notes

- `pr edit -l`, `-a`, `-r` and `issue edit -l`, `-a` **set** the full list (replace), they do
  not append. Read the current labels first and pass the union.
- `-m/--milestone` (0.10.1 drivers): **GitHub** — milestone *number* only (a title is
  silently ignored); **Gitea/Forgejo** — resolved by title or ID; **GitLab** — not applied
  at all, use the API (`api-recipes.md`). `forge pr edit` has no milestone flag — on
  GitHub/Gitea a PR is also an issue, so use `forge issue edit <pr-number> -m <number>`.
  Always read back (`forge pr view N -o json | jq .milestone`) after setting.
- `pr merge` without `-m` uses the forge's default method. `-d` deletes the head branch.
- `pr review` has `approve` and `reject` (request changes) only; a neutral "comment" review
  needs `forge api` (see `api-recipes.md`), or use `forge pr comment`.
- `status list <sha>` shows legacy commit statuses only; GitHub Actions/Checks results are
  check runs → `forge ci list -b <branch>` or the check-runs endpoint.
- `ci view <run>` prints the run and its job IDs; `ci log` takes a **job** ID, not a run ID.
- `secret set -v VALUE` puts the secret on the command line — let the user run it.
- `auth status` prints `token from config|env`, `no token`, and for token commands the
  command line itself — don't paste that output into reports.
- Config precedence: CLI flags > env vars (`FORGE_TOKEN`, `GITHUB_TOKEN`/`GH_TOKEN`,
  `GITLAB_TOKEN`, `FORGEJO_TOKEN`/`GITEA_TOKEN`, `BITBUCKET_TOKEN`, `TANGLED_TOKEN`) > repo
  `.forge` (committed; `[default] remote=…`, per-host `type=…`, never tokens) >
  `~/.config/forge/config` (`[host] token=…` or `token-cmd=…`, `scheme=http`,
  `[default] output=json`) > defaults.

## JSON shapes (`-o json`, normalized across forges)

| Object | Fields |
|---|---|
| PullRequest | `number title body state(open\|closed\|merged) draft author{login} assignees[] reviewers[] labels[{name,color}] milestone{title,number,state} head{ref,sha} base{ref,sha} mergeable merged merged_by comments additions deletions changed_files html_url diff_url created_at updated_at merged_at closed_at` |
| Issue | `number title body state author assignees[] labels[] milestone comments locked html_url created_at updated_at closed_at` |
| Milestone | `title number description state due_date` (no issue counts — use the API) |
| Label | `name color description` |
| CIRun | `id title status conclusion branch sha event author html_url jobs[] created_at updated_at finished_at` |
| Review | `id state(approved\|changes_requested\|commented\|dismissed\|pending) body author html_url submitted_at` |

Optional fields (`milestone`, `labels`, `assignees`, …) are omitted when empty: use
`jq '.milestone.title // "none"'`.
