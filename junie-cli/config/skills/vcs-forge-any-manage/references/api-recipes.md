# `forge api` recipes for features the native commands lack

`forge api <endpoint>` prepends the forge's API root (GitHub `https://api.github.com/`,
GitLab `https://<host>/api/v4/`, Gitea/Forgejo `https://<host>/api/v1/`) and substitutes
`{owner}` and `{repo}` from the resolved repository. Limits (forge 0.10.1):

- `-f KEY=VALUE` builds a JSON object whose values are all **strings**. GitHub tolerates
  strings for some numeric fields (e.g. `milestone`); Gitea/Forgejo (Go, strict) reject them;
  GitLab coerces them. Avoid endpoints that require integers/booleans/arrays — use the
  native command or an endpoint variant that takes only strings (e.g. GitHub's `…/replies`).
- No stdin/`--input`, no `--paginate`, no `--jq`: pipe to `jq`; page lists with
  `scripts/api-pages.sh`.
- `-X POST|PATCH|PUT|DELETE` for writes; `--silent` to drop the body; `-i` for headers.

All writes need user approval like any other mutation.

## GitHub

```bash
PR=$(forge pr view -o json | jq -r .number)        # PR of the current branch

# Inline review comments (originals only) — all pages
scripts/api-pages.sh "repos/{owner}/{repo}/pulls/$PR/comments" |
  jq '[.[] | select(.in_reply_to_id == null) | {id, path, line, user: .user.login, created_at, body: .body[0:200]}]'

# Unreplied original comments
scripts/api-pages.sh "repos/{owner}/{repo}/pulls/$PR/comments" | jq '
  [.[] | select(.in_reply_to_id) | .in_reply_to_id] as $replied |
  [.[] | select(.in_reply_to_id == null) | select(.id | IN($replied[]) | not) | .id]'

# Reviews (raw, with bodies) and the comments attached to one review
scripts/api-pages.sh "repos/{owner}/{repo}/pulls/$PR/reviews" |
  jq '[.[] | select(.body | length > 0) | {id, user: .user.login, state, submitted_at, body: .body[0:500]}]'
scripts/api-pages.sh "repos/{owner}/{repo}/pulls/$PR/reviews/$REVIEW_ID/comments"

# Reply in an inline review thread (body only — in_reply_to would be sent as a string)
forge api -X POST "repos/{owner}/{repo}/pulls/$PR/comments/$COMMENT_ID/replies" \
  -f body="Fixed in $(git rev-parse --short HEAD). Brief explanation." | jq '{id, html_url}'

# Neutral review ("comment" event; approve/request-changes have native commands)
forge api -X POST "repos/{owner}/{repo}/pulls/$PR/reviews" -f event=COMMENT -f body="Progress update …"

# Milestone of a PR, open milestones, counts, close
forge pr view "$PR" -o json | jq -r '.milestone.title // "none"'
forge milestone list -s open -o json | jq -r '.[]? | "\(.number): \(.title)"'
forge api "repos/{owner}/{repo}/milestones/$M" | jq -r '"Open: \(.open_issues) | Closed: \(.closed_issues) | \(.title)"'
forge milestone close "$M"

# Checks for the PR head: Actions/Checks + legacy statuses
SHA=$(forge pr view "$PR" -o json | jq -r .head.sha)
forge api "repos/{owner}/{repo}/commits/$SHA/check-runs?per_page=100" |
  jq -r '.check_runs[] | "\(.conclusion // .status)\t\(.name)"'
forge api "repos/{owner}/{repo}/commits/$SHA/status" | jq -r '.state, (.statuses[] | "\(.state)\t\(.context)")'

# Current user (for "assigned to me")
forge api user | jq -r .login

# Mark a draft PR ready / convert to draft — GraphQL only on GitHub; ask the user to use the web UI
```

Check-runs/combined-status responses are objects, not arrays — use plain `forge api`, not
`api-pages.sh`. All checks green ⇔ every check run has `conclusion` in
`success|neutral|skipped` and the combined status is `success` **or has zero statuses**
(GitHub reports `state: "pending"` when no legacy statuses exist):

```bash
forge api "repos/{owner}/{repo}/commits/$SHA/check-runs?per_page=100" |
  jq -e '[.check_runs[] | select((.conclusion // "pending") | IN("success","neutral","skipped") | not)] | length == 0'
forge api "repos/{owner}/{repo}/commits/$SHA/status" |
  jq -e '(.statuses | length) == 0 or .state == "success"'
```

## GitLab (project path must be URL-encoded: `{owner}%2F{repo}`)

For subgroups `{owner}` contains `/`; if the call 404s, spell the path out with `%2F`
between every segment.

```bash
P='projects/{owner}%2F{repo}'
MR=$(forge pr view -o json | jq -r .number)           # MR IID

scripts/api-pages.sh "$P/merge_requests/$MR/discussions" |
  jq '[.[] | select(.individual_note == false) | {id, resolved: .notes[0].resolved, path: .notes[0].position.new_path, author: .notes[0].author.username, body: .notes[0].body[0:200]}]'
forge api -X POST "$P/merge_requests/$MR/discussions/$DISCUSSION_ID/notes" -f body="Fixed in …"
forge api -X PUT  "$P/merge_requests/$MR/discussions/$DISCUSSION_ID" -f resolved=true
forge api -X POST "$P/merge_requests/$MR/notes" -f body="General comment"
forge api -X PUT  "$P/merge_requests/$MR" -f milestone_id="$MILESTONE_ID"     # forge -m is ignored on GitLab
forge api "$P/merge_requests/$MR/pipelines" | jq '.[0] | {id, status, web_url}'
forge api "$P/milestones/$MILESTONE_ID/issues" | jq '[.[] | select(.state == "opened")] | length'
```

## Gitea / Forgejo / Codeberg

```bash
PR=$(forge pr view -o json | jq -r .number)
scripts/api-pages.sh -p 50 "repos/{owner}/{repo}/pulls/$PR/reviews" | jq '[.[] | {id, state, user: .user.login, body: .body[0:300]}]'
scripts/api-pages.sh -p 50 "repos/{owner}/{repo}/pulls/$PR/reviews/$REVIEW_ID/comments"
forge api -X POST "repos/{owner}/{repo}/pulls/$PR/reviews" -f event=COMMENT -f body="…"
forge api "repos/{owner}/{repo}/commits/$SHA/status" | jq '{state, statuses: [.statuses[] | {context, status}]}'
forge api "repos/{owner}/{repo}/milestones/$M" | jq '{title, open_issues, closed_issues}'
```

Gitea has no "reply to review comment" endpoint: answer with `forge pr comment N -b "…"`
quoting the file:line. Integer fields (`milestone`, `assignee ids`) must go through native
commands (`forge issue edit N -m …`), not `forge api -f`.

## Bitbucket, Gerrit, Tangled

Use native commands only unless the user provides API details; check `forge <cmd> --help`
and expect some commands to be unsupported (forge reports an error).
