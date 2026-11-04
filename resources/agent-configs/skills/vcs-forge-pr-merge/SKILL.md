---
name: vcs-forge-pr-merge
description: Merges GitHub Pull Requests (and GitLab/Gitea/Forgejo merge/pull requests) with the forge CLI after validating a pre-merge checklist. Use when the user explicitly asks to merge a PR, close a PR, finalize a PR, complete a merge, approve and merge, or execute a merge. Runs pre-merge validation (tests, lint, CI, comments), confirms with the user, merges with the project format, and handles post-merge cleanup.
model: haiku
---

# Pull request merge (forge)

Merges Pull Requests after validating a pre-merge checklist and handling post-merge cleanup.
Forge operations use `forge` (git-pkgs/forge); `gh` is not used. API endpoints below are
GitHub's — for GitLab/Gitea equivalents see `../vcs-forge-any-manage/references/api-recipes.md`.

**Junie note:** Junie never merges or deletes branches without explicit user
confirmation. Show the full pre-merge checklist and wait for an explicit "go ahead"
from the user before running `forge pr merge`.

## Inspect current PR

```bash
../vcs-forge-any-manage/scripts/forge-ctx.sh      # host/repo, PR of this branch, auth present (exit 3 = none)
forge pr view -o json | jq -r '"PR #\(.number): \(.title) (\(.state)) \(.head.ref) -> \(.base.ref)"'
```

## Core workflow

### 1. Check comments status

Verify all review comments have at least one reply:

```bash
PAGES=../vcs-forge-any-manage/scripts/api-pages.sh   # forge api has no --paginate
PR=$(forge pr view -o json | jq -r '.number')

# Find unreplied comment IDs ({owner}/{repo} are filled in by forge)
$PAGES "repos/{owner}/{repo}/pulls/$PR/comments" | jq '
  [.[] | select(.in_reply_to_id) | .in_reply_to_id] as $replied |
  [.[] | select(.in_reply_to_id == null) | select(.id | IN($replied[]) | not) | .id]
'
```

**If unreplied comments exist:**
- **STOP** the merge process
- Inform the user: "Found unreplied comments: [IDs]. Run vcs-forge-pr-review first."
- **NEVER** reply to comments from this skill

### 2. Check milestone

```bash
forge pr view "$PR" -o json | jq -r '.milestone.title // "none"'
```

- If milestone is assigned: include it in the checklist summary (step 3)
- If no milestone: check for open milestones and warn the user

```bash
forge milestone list -s open -o json | jq 'length? // 0'
```

If open milestones exist but the PR has none, surface a warning in the checklist:
`- Milestone: ⚠ not assigned (open milestones exist)`

Do **not** block the merge for a missing milestone. It is a warning only.

### 3. Run validation

Run tests, linting, and verify CI checks. All **MUST** pass before proceeding.

```bash
HEAD_REF=$(forge pr view "$PR" -o json | jq -r .head.ref)
SHA=$(forge pr view "$PR" -o json | jq -r .head.sha)
forge ci list -b "$HEAD_REF" -L 20                     # workflow runs on the PR branch
# GitHub: every check run on the head commit must be green, and legacy statuses success/absent
forge api "repos/{owner}/{repo}/commits/$SHA/check-runs?per_page=100" |
  jq -r '.check_runs[] | "\(.conclusion // .status)\t\(.name)"'
forge api "repos/{owner}/{repo}/commits/$SHA/status" |
  jq -e '(.statuses | length) == 0 or .state == "success"'
```

A failing run: `forge ci view <run-id>` lists its jobs, `forge ci log <job-id>` prints the
log. (`gcli pulls -i "$PR" ci` gives the same check overview in table form.)

### 4. Confirm with user

**ALWAYS show the checklist summary and ask before merging:**

```
Pre-merge checklist:
- Comments: all replied
- Tests: passing
- Lint: passing
- CI: green
- Milestone: v0.1.0 (or ⚠ not assigned)

Ready to merge PR #X. Proceed?
```

### 5. Execute merge

Write the approved merge message to `/tmp/merge-msg.md`, then:

```bash
forge pr merge "$PR" --method merge --delete-branch \
  --commit-message "$(cat /tmp/merge-msg.md)"      # title: the forge's default merge title
forge pr view "$PR" -o json | jq '{state, merged, merged_by: .merged_by.login}'
```

**Merge strategy:** always `--method merge` (merge commit), never squash or rebase.

`--delete-branch` deletes the remote head branch after the merge.

### 6. Post-merge cleanup

```bash
git checkout develop && git pull origin develop
```

### 7. Check milestone completion

If the PR had a milestone, check whether all items are now closed:

```bash
MILESTONE=$(forge pr view "$PR" -o json | jq -r '.milestone.number // empty')
if [ -n "$MILESTONE" ]; then
  # forge's milestone JSON has no issue counts; read them from the API (GitHub/Gitea)
  forge api "repos/{owner}/{repo}/milestones/$MILESTONE" |
    jq -r '"Open: \(.open_issues) | Closed: \(.closed_issues) | \(.title)"'
fi
```

- If `open_issues == 0`: inform the user and ask whether to close the milestone

```bash
forge milestone close "$MILESTONE"
```

- If `open_issues > 0`: report remaining open items count. No action needed.
- **NEVER** close a milestone automatically without explicit user confirmation.

## Merge message format

Concise format for a clean git log:

```
- Key change 1 (what was added/fixed)
- Key change 2
- Key change 3

Reviews: 7/7 addressed (Gemini 5, Codex 2)
Tests: 628 passed (88% cov)
Refs: Task 8, Req 14-15
```

- 3-5 bullet points max for changes
- One line each for reviews summary, test results, and task references
- No headers (`##`), no verbose sections
- Total: ~10 lines max

## Important rules

- **ALWAYS** run tests, lint, and CI checks before merging
- **ALWAYS** verify all review comments have replies
- **ALWAYS** check milestone assignment before merging (warn if missing, do not block)
- **ALWAYS** confirm with the user before executing the merge
- **ALWAYS** use a merge commit (`--method merge`), never squash/rebase
- **ALWAYS** delete the feature branch after a successful merge
- **ALWAYS** check milestone completion after merge and report remaining open items
- **NEVER** merge with failing tests, lint, or CI checks
- **NEVER** skip user confirmation
- **NEVER** close a milestone without explicit user confirmation
- **NEVER** reply to PR comments from this skill — use the vcs-forge-pr-review skill instead
- **STOP** the merge if unreplied comments exist and direct the user to the review skill
