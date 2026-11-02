---
name: vcs-forge-pr-review
description: Handles PR review comments and feedback resolution. Use when the user explicitly asks to resolve PR comments, handle review feedback, fix review comments, address PR review, check review status, respond to reviewer, verify PR readiness, review PR comments, analyze review feedback, evaluate PR comments, assess review suggestions, or triage PR comments. Fetches comments via the forge CLI (git-pkgs/forge; GitHub API, with GitLab/Gitea notes), classifies by severity, proposes fixes for user approval, commits with proper format, and replies to threads.
---

# Pull request review (forge)

Resolves Pull Request review comments with severity-based prioritization, fix application, and thread replies.
Forge operations use `forge` (git-pkgs/forge); `gh` is not used. The endpoints below are
GitHub's; GitLab discussions and Gitea reviews are in
`../vcs-forge-any-manage/references/api-recipes.md`. `gcli pulls -i "$PR" discussions` prints
GitHub review threads in readable form if you only need to read them.

**Junie note:** Junie does not modify files, commit, or reply to threads without
explicit user confirmation. Always show the review summary table and per-comment
fix proposal first; act only after the user approves.

## Inspect current PR

```bash
../vcs-forge-any-manage/scripts/forge-ctx.sh      # host/repo, PR of this branch, auth present (exit 3 = none)
forge pr view -o json |
  jq -r '"PR #\(.number): \(.title) (\(.state)) | Milestone: \(.milestone.title // "none")"'
```

## Core workflow

### 1. Fetch, filter, and classify comments

```bash
PAGES=../vcs-forge-any-manage/scripts/api-pages.sh   # forge api has no --paginate
PR=$(forge pr view -o json | jq -r '.number')
LAST_PUSH=$(git log -1 --format=%cI HEAD)

# Inline review comments - filter out replies (keep only originals)
# ({owner}/{repo} are filled in by forge from the git remote)
$PAGES "repos/{owner}/{repo}/pulls/$PR/comments" | jq '
  [.[] | select(.in_reply_to_id == null) |
   {id, path, user: .user.login, created_at, body: .body[0:200]}]
'

# PR-level reviews with non-empty body (CodeRabbit sections, Gemini, etc.)
$PAGES "repos/{owner}/{repo}/pulls/$PR/reviews" | jq '
  [.[] | select(.body | length > 0) |
   {id, user: .user.login, state, submitted_at, body: .body[0:500]}]
'
```

**Cross-check review-attached comments:** CodeRabbit's review body states "Actionable
comments posted: N". If the general `pulls/$PR/comments` endpoint returns fewer
than N new originals from that reviewer, some comments are only available via the
review-specific endpoint. Fetch them and merge by comment ID:

```bash
# $REVIEW_ID from the reviews fetch above; $EXPECTED from parsing "Actionable comments posted: N"
$PAGES "repos/{owner}/{repo}/pulls/$PR/reviews/$REVIEW_ID/comments" | jq '
  [.[] | select(.in_reply_to_id == null) |
   {id, path, user: .user.login, created_at, body: .body[0:200]}]
'
```

Deduplicate by `id` before continuing. Comments found only via the review-specific
endpoint are valid inline comments and should be treated identically (same
classification, same `in_reply_to` reply mechanism).

**Filter new vs already-seen:** compare `created_at`/`submitted_at` with `$LAST_PUSH`.
Comments posted after the last push are new. Mark older comments as "previous round"
in the summary table.

**Parse CodeRabbit review bodies:** the initial fetch truncates bodies for
classification. For reviews from CodeRabbit (`user.login` starts with `coderabbitai`),
fetch the full body separately:

```bash
$PAGES "repos/{owner}/{repo}/pulls/$PR/reviews" | jq '
  [.[] | select(.user.login | startswith("coderabbitai")) |
   {id, submitted_at, body}]
'
```

CodeRabbit posts structured `<details>` blocks containing outside-diff, duplicate,
and nitpick comments. Each block includes file path, line range, severity, and
optionally a "Prompt for AI Agents" with pre-built context. See
`references/coderabbit_parsing.md` for the full parsing guide.

**Use CodeRabbit AI prompts when available:** if a comment (or the review body)
contains a "Prompt for AI Agents" `<details>` block, use it to understand the issue
and the suggested approach. Always read the actual code before proposing a fix.
If the review body contains a "Prompt for all review comments with AI agents" block,
read it first for cross-comment context before processing individual comments.

Classify all comments by severity and process in order: CRITICAL > HIGH > MEDIUM > LOW.

| Severity | Indicators | Action |
|----------|------------|--------|
| CRITICAL | `critical.svg`, `_🔒 Security_`, `_🚨 Critical_`, `_🔴 Critical_`, "security", "vulnerability" | Must fix |
| HIGH | `high-priority.svg`, `_⚠️ Potential issue_`, `_🐛 Bug_`, `_⚡ Performance_`, `_🟠 Major_`, "High Severity" | Should fix |
| MEDIUM | `medium-priority.svg`, `_🛠️ Refactor suggestion_`, `_💡 Suggestion_`, "Medium Severity" | Recommended |
| LOW | `low-priority.svg`, `_🧹 Nitpick_`, `_🔧 Optional_`, `_🟡 Minor_`, `_🔵 Trivial_`, `_⚪ Info_`, "style", "nit" | Optional |

When a comment has both a type label and a secondary color badge (e.g.,
`_💡 Suggestion_ | _🟠 Major_`), the color badge is the **binding** severity and
overrides the type-based default.

See `references/severity_guide.md` for full detection patterns (Gemini badges,
CodeRabbit emoji, Cursor comments, keyword fallback, related comments heuristics).

### 2. Show review summary table

Before processing, display a structured overview of all comments:

```
| # | ID         | Severity | File:Line          | Type     | Status   | Summary            |
|---|------------|----------|--------------------|----------|----------|--------------------|
| 1 | 123456789  | CRITICAL | src/auth.py:45     | inline   | new      | SQL injection risk |
| 2 | 987654321  | HIGH     | src/db.py:346-350  | outside  | new      | Missing join cond  |
| 3 | 555555555  | HIGH     | src/chunk.py:188   | duplicate| previous | Stale metadata     |
| 4 | 444444444  | LOW      | tests/test_q.py:12 | nitpick  | previous | Naming convention  |
```

- **Type:** `inline`, `outside` (outside diff), `duplicate`, `minor`, `nitpick`
  (from CodeRabbit sections), or `review` (generic PR-level)
- **Status:** `new` (posted after last push) or `previous` (from earlier rounds)
- Group related comments (same file, same root cause, "also applies to" ranges)
  and note clusters
- Deduplicate: if the same issue appears both as an inline comment and in a
  CodeRabbit review body section (e.g., duplicate), keep one entry and note both sources

If there are **more than 10 comments**, suggest saving a review summary to
`.junie/memory/` for tracking across sessions. The summary should include: PR
number, comment IDs, severity, status (new/addressed/deferred/won't fix), and
brief description. This helps maintain continuity when new comments arrive after
subsequent pushes.

### 3. Process each comment

For each comment, in severity order:

1. **Show context:** comment ID, severity, file:line, quote
2. **Check for AI prompt:** if a CodeRabbit "Prompt for AI Agents" is available
   for this comment, use it to understand the issue and suggested approach
3. **Check for proposed fix:** if CodeRabbit includes a "Proposed fix" or
   "Suggested fix" code block, use it as a starting point (but verify correctness)
4. **Read affected code** and propose a fix (always read the actual code, even
   when an AI prompt or proposed fix provides context)
5. **Handle "also applies to":** if the comment references additional line ranges,
   include all locations in the fix
6. **Confirm with the user** before applying
7. **Apply the fix** if approved
8. **Verify ALL issues** in the comment are addressed (multi-issue comments are common)

### 4. Commit changes

Use the `vcs-git-commit-create` skill format. Functional fixes get separate commits, cosmetic
fixes are batched:

| Change type | Strategy |
|-------------|----------|
| Functional (CRITICAL/HIGH) | Separate commit per fix |
| Cosmetic (MEDIUM/LOW) | Single batch `style:` commit |

Reference the comment ID in the commit body. Commits require user approval per the
Junie general guideline that Junie does not commit autonomously.

### 5. Reply to threads

#### Inline comments

**Important:** use the `replies` endpoint. `forge api -f` sends every value as a string, so
posting `in_reply_to` to `pulls/$PR/comments` does NOT work; the replies endpoint needs only
a `body`.

```bash
COMMIT=$(git rev-parse --short HEAD)
forge api -X POST "repos/{owner}/{repo}/pulls/$PR/comments/123456789/replies" \
  -f body="Fixed in $COMMIT. Brief explanation." | jq '{id, html_url}'
```

#### Non-inline comments (CodeRabbit review body)

Comments embedded in the review body (outside diff, duplicate, nitpick) do not have
inline threads. The GitHub API does not support replying to a review body directly.
Post a general PR comment referencing the specific issue:

```bash
forge pr comment "$PR" -b "Fixed in $COMMIT. Addresses outside-diff comment on file/path.py:346-350."
```

**Reply templates** (no emojis, minimal and professional):

| Situation | Template |
|-----------|----------|
| Fixed | `Fixed in [hash]. [brief description of fix]` |
| Won't fix | `Won't fix: [reason]` |
| By design | `By design: [explanation]` |
| Deferred | `Deferred to [issue/task]. Will address in future iteration.` |
| Acknowledged | `Acknowledged. [brief note]` |

### 6. Run tests and push

Run the project test suite. All tests must pass before pushing. Push all fixes
together to minimize review loops.

### 7. Submit review (optional)

After addressing all comments, formally submit a review:

- `forge pr review approve "$PR" -b "..."` — all comments addressed, PR is ready
- `forge pr review reject "$PR" -b "..."` — critical issues remain (request changes)
- `forge api -X POST "repos/{owner}/{repo}/pulls/$PR/reviews" -f event=COMMENT -f body="..."`
  — progress update, no decision yet (forge has no native "comment" review)

Forges do not allow approving or requesting changes on your own PR; on your own PR use
the comment form or `forge pr comment`.

### 8. Verify milestone

```bash
forge pr view "$PR" -o json | jq -r '.milestone.title // "none"'
```

If the PR has no milestone, check for open milestones:

```bash
forge milestone list -s open -o json | jq -r '.[]? | "\(.number): \(.title)"'
```

If open milestones exist, inform the user and suggest assigning (a PR is an issue on
GitHub/Gitea, and `forge pr edit` has no milestone flag; GitHub needs the **number**):

```bash
forge issue edit "$PR" -m [milestone-number]
forge pr view "$PR" -o json | jq -r '.milestone.title // "not set"'   # verify
```

Do **not** assign automatically. This is a reminder only.

## Avoiding review loops

When bots (Gemini, Codex, etc.) review every push:

1. **Batch fixes:** accumulate all fixes, push once
2. **Draft PR:** convert to draft during fixes
3. **Commit keywords:** some bots respect `[skip ci]` or `[skip review]`

## Important rules

- **ALWAYS** fetch both inline comments (`pulls/$PR/comments`) and review bodies
  (`pulls/$PR/reviews`)
- **ALWAYS** cross-check "Actionable comments posted: N" against found originals;
  fetch `pulls/$PR/reviews/$REVIEW_ID/comments` when count mismatches
- **ALWAYS** parse CodeRabbit review bodies for all section types (outside diff,
  duplicate, minor, nitpick)
- **ALWAYS** use CodeRabbit "Prompt for AI Agents" as primary context when available
- **ALWAYS** show the review summary table before processing
- **ALWAYS** confirm with the user before modifying files
- **ALWAYS** verify ALL issues in multi-issue comments are fixed, including
  "also applies to" ranges
- **ALWAYS** run tests before pushing
- **ALWAYS** reply to resolved threads using the standard templates
- **ALWAYS** submit a formal review (`forge pr review approve|reject`, or a COMMENT review via `forge api`) after addressing all comments
- **ALWAYS** check milestone at the end and remind if missing
- **ALWAYS** suggest saving a review summary to `.junie/memory/` when there are
  more than 10 comments
- **NEVER** use emojis in commit messages or thread replies
- **NEVER** skip HIGH/CRITICAL comments without explicit user approval
- **NEVER** assign a milestone automatically — suggest only
- **Functional fixes** → separate commits (one per fix)
- **Cosmetic fixes** → batch into a single `style:` commit
- **Duplicate comments** → treat as higher priority than their label (issue was
  already flagged before)
- **Related comments** → group and fix together when they share root cause or
  file context

## References

- `references/severity_guide.md` — Severity detection patterns (Gemini badges,
  CodeRabbit emoji, Cursor comments, keyword fallback, related comments heuristics)
- `references/coderabbit_parsing.md` — CodeRabbit review body structure, section
  parsing, "Prompt for AI Agents" usage, duplicate and "also applies to" handling
- `../vcs-forge-any-manage/references/api-recipes.md` — forge api endpoints (GitHub,
  GitLab discussions, Gitea reviews) and the string-only `-f` limitation
