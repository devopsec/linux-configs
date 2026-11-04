---
name: vcs-forge-pr-create
description: Creates GitHub Pull Requests (and GitLab/Gitea/Forgejo merge/pull requests) with the forge CLI, automated validation, and task tracking. Use when the user explicitly asks to create a PR, open a pull request, submit for review, or check if work is ready for PR. Analyzes commits, validates task completion, generates Conventional Commits title and description, and suggests labels. NOTE — for merging existing PRs, use the vcs-forge-pr-merge skill instead.
model: haiku
---

# Pull request creation (forge)

Creates Pull Requests with task validation, test execution, and Conventional Commits formatting.
Forge operations use `forge` (git-pkgs/forge); `gh` is not used. Command details and
gh→forge translations: `../vcs-forge-any-manage/SKILL.md`.

**Junie note:** Junie does not push or open PRs autonomously. Run the commands
below only after the user has approved both the proposed PR title and body.

## Inspect current state

```bash
git rev-parse --abbrev-ref HEAD
git log @{u}..HEAD --oneline   # commits not yet on the upstream branch
../vcs-forge-any-manage/scripts/forge-ctx.sh   # remote/host/repo, existing PR for this branch, auth present?
```

If `forge-ctx.sh` exits 3 (no token), the PR cannot be created: ask the user to run
`forge auth login --domain <host> --token-cmd '…'` themselves. If it already shows a PR for
this branch, update that PR (`forge pr edit`) instead of creating a duplicate.

## Core workflow

### 1. Confirm target branch

**ALWAYS ask the user before proceeding:**

```
Creating PR from [current-branch] to [target-branch]. Correct?
```

| Branch flow | Typical target |
|-------------|---------------|
| feature/*   | develop |
| fix/*       | develop |
| hotfix/*    | main/master |
| develop     | main/master |

### 2. Search for task documentation

Look for task/spec files that describe what this PR should accomplish. Common locations:

| Tool/Convention | Path |
|-----------------|------|
| Spec2Ship (s2s) | `.s2s/plans/*.md` (look for active plan matching branch name or commits) |
| AWS Kiro | `.kiro/specs/*/tasks.md` |
| Cursor | `.cursor/rules/*.md`, `.cursorrules` |
| Trae | `.trae/rules/*.md` |
| Junie | `.junie/plans/*.md`, `documentation/agent/*.md` |
| Forge issues | `forge issue list -a "$(forge api user \| jq -r .login)" -s open` (GitHub; on other forges pass your username) |
| Generic | `docs/specs/`, `specs/`, `tasks.md`, `TODO.md` |

Extract task IDs, titles, descriptions, and requirements references when found.

### 3. Analyze commits

For each commit on this branch, identify type, scope, task references, and breaking
changes. Map commits to documented tasks when task files exist.

### 4. Verify task completion

If task documentation exists:

1. Identify the main task from the branch name (e.g., `feature/task-2-*` -> Task 2)
2. Find all sub-tasks (e.g., Task 2.1, 2.2, 2.3)
3. Check which sub-tasks are referenced in commits
4. Report missing sub-tasks

**If tasks are incomplete, STOP and show status:**

```
Task 2 INCOMPLETE: 1/3 sub-tasks missing
- Task 2.1: done
- Task 2.2: done
- Task 2.3: MISSING
```

Ask the user whether to complete missing tasks or proceed anyway.

### 5. Run tests

Run the project test suite. Tests **MUST** pass before creating the PR.

### 6. Determine PR type and generate title

| Branch flow | Title prefix |
|-------------|-------------|
| feature/* -> develop | `feat(scope):` |
| fix/* -> develop | `fix(scope):` |
| hotfix/* -> main | `hotfix(scope):` |
| develop -> main | `release:` |
| refactor/* -> develop | `refactor(scope):` |
| chore/* -> develop | `chore(scope):` |
| ci/* -> develop | `ci(scope):` |
| docs/* -> develop | `docs(scope):` |

**Title format:** `<type>(<scope>): <description>`
- Type: dominant commit type from analysis (feat > fix > refactor > ci > chore)
- Scope: most common scope from commits (kebab-case)
- Description: imperative, lowercase, no period, max 50 chars

**Breaking changes:** if any commit contains `BREAKING CHANGE:` or `!` after the type:
- Add a `breaking` label if it exists in the project
- Include a `## Breaking changes` section in the PR body

### 7. Generate PR body

Use the appropriate template from `references/pr_templates.md` based on PR type
and populate with gathered data.

### 8. Suggest labels

**ALWAYS check available labels first:**

```bash
forge label list -o json | jq -r '.[] | "\(.name)\t\(.description // "")"'
```

Match commit types to available project labels. The project may use different
names than standard (e.g., "feature" instead of "enhancement").

| Commit type | Common label names |
|-------------|-------------------|
| feat | feature, enhancement |
| fix | bug, bugfix |
| refactor | refactoring, tech-debt |
| docs | documentation |
| ci | ci/cd, infrastructure |
| security | security |
| hotfix | urgent, priority:high |

**If no matching label exists:** suggest creating one. The user may have removed
default labels, so offering to add relevant ones is appropriate.

### 9. Determine milestone

Check for open milestones:

```bash
forge milestone list -s open -o json | jq -r '.[]? | "\(.number): \(.title)"'
```

- If one active milestone exists: assign the PR to it (pass its **number** to `-m`; on
  GitHub a title is silently ignored, on GitLab `-m` is ignored — set it afterwards via the
  API, see `../vcs-forge-any-manage/references/api-recipes.md`)
- If multiple exist: ask the user which one applies
- If none exist: skip (do not create one automatically)

### 10. Create PR

**ALWAYS show title, body, labels, and milestone for user approval first.**

Write the approved body to a scratch file (e.g. `/tmp/pr-body.md`), push the branch
(`git push -u origin HEAD`, or add `--push`), then:

```bash
forge pr create \
  --title "[title]" \
  --body "$(cat /tmp/pr-body.md)" \
  --base [base_branch] \
  --head [current_branch] \
  --label "[label1]" --label "[label2]" \
  --milestone [milestone-number] \
  --reviewer "[username]"
```

Use `--draft` if the PR is not ready for merge review yet (work in progress,
awaiting CI, or created only to trigger an AI bot review on the branch).

Verify what was created (labels/milestone are applied in a second API call and can fail
separately):

```bash
forge pr view -o json | jq '{number, html_url, draft, labels: [.labels[]?.name], milestone: (.milestone.title // "none")}'
```

## Important rules

- **ALWAYS** confirm target branch with the user
- **ALWAYS** run tests before creating the PR
- **ALWAYS** show the full PR content for approval before creating
- **ALWAYS** check available labels with `forge label list` before suggesting
- **ALWAYS** pass the body from a file (`--body "$(cat /tmp/pr-body.md)"`) to preserve formatting
- **ALWAYS** add `--label` for each label separately (not comma-separated in one string)
- **ALWAYS** check for open milestones and assign if one is active (by number)
- **NEVER** create a PR without user confirmation
- **NEVER** modify repository files from this skill (read-only analysis)
- **NEVER** create a milestone automatically — only assign existing ones
- Use `--draft` for PRs not ready for merge review
- Use `--reviewer` when teammates are known from team config or CODEOWNERS

## References

- `references/pr_templates.md` — PR body templates for all types (feature, release, bugfix, hotfix, refactoring, docs, CI/CD)
- `../vcs-forge-any-manage/SKILL.md` — forge commands, pre-flight, API gaps; `../vcs-gcli-any-manage/SKILL.md` if the user prefers gcli
