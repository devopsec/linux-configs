---
name: vcs-forge-any-manage
description: "Operate GitHub, GitLab, Gitea/Forgejo/Codeberg, Bitbucket Cloud, Gerrit, and Tangled from the command line with git-pkgs/forge (`forge`): pull/merge requests (list, view, diff, checkout, create, edit, comment, review, merge), issues, labels, milestones, CI runs and job logs, commit statuses, releases, repos, secrets, notifications, and raw REST calls (`forge api`) with JSON output for scripting. Use when a task needs a git forge from the terminal, when replacing or translating `gh`/`glab`/`tea` commands, when the user mentions forge, PRs/MRs, CI status, or releases on a non-GitHub forge, or when other vcs-* skills need forge operations. For gcli (herrhotzenplotz/gcli) or Bugzilla use vcs-gcli-any-manage."
model: haiku
---

# forge (git-pkgs/forge)

`forge` (Go, MIT) is one CLI for many forges. It detects host, owner, and repo from the git
remote, takes everything as flags (no editor prompts), and prints `-o json` for `jq`. It is
the default replacement for `gh` in this environment; `gh` is not used.

Verified against forge 0.10.1. Run `forge <cmd> --help` when a flag is not in the references.

## Ground rules

- **Pre-flight before writes**: `scripts/forge-ctx.sh` (read-only). It shows the remote,
  host, slug, current-branch PR, rate limit, and whether a token exists (never its value).
  Exit 3 = no token → reads only; ask the user to authenticate (below). Confirm the target
  repo/branch with the user before anything that mutates the forge.
- **Read before write**: list/view the PR, issue, milestone, or run before editing,
  commenting, merging, closing, or deleting. Show the exact command and content (title, body,
  labels, milestone) and get approval for every mutating call.
- **Machine output**: `-o json` + `jq`. JSON is normalized across forges (fields in
  `references/commands.md`), not the raw forge API shape.
- **Target selection**: inside a checkout forge uses the `.forge` `remote` or `origin`;
  `--remote upstream` picks another remote; `-R owner/repo` (or `HOST/OWNER/REPO`) targets any
  repo; `--host` / `--forge-type` for self-hosted or ambiguous hosts. `FORGE_HOST` only
  affects `-R` and non-repo commands.
- **Gaps → `forge api`**: when a native command lacks a feature (inline review threads,
  replies, neutral "comment" reviews, check runs, milestone issue counts), use `forge api`
  with the endpoint recipes in `references/api-recipes.md`. `{owner}`/`{repo}` placeholders are
  substituted. `-f KEY=VALUE` sends a JSON object of **strings only** (no integers, booleans,
  arrays, or stdin body): prefer endpoints whose required fields are strings, or the native
  command. No `--paginate`/`--jq`: use `scripts/api-pages.sh` and pipe to `jq`.
- **Secrets**: never pass tokens on the command line or print them. Auth is the user's step:
  `! forge auth login --domain <host> --token-cmd 'pass show forge/<host>'` (or `rbw get …`).
  `forge secret set -v` exposes the value in the process list and history — hand that command
  to the user instead of running it.
- No force pushes, branch deletions, merges, releases, or repo deletion without explicit
  confirmation. Never commit from this skill (`vcs-git-commit-create` handles commits).

## Workflow

1. **Context**: `scripts/forge-ctx.sh [-r remote] [-n]` — note host, slug, PR number, auth.
2. **Load references** as needed:

   ```sadkitti
   IF need exact flags, JSON fields, or a command not shown below
     REFERENCE "references/commands.md"
   IF native forge command lacks the feature (review threads, replies, check runs, milestone counts, GitLab discussions)
     REFERENCE "references/api-recipes.md"
   IF translating gh/glab/tea commands, scripts, or docs to forge or gcli
     REFERENCE "references/gh-migration.md"
   ```

3. **Read** the current state (`forge pr view [N] -o json`, `forge issue view N -c`,
   `forge ci list -b <branch>`), then **propose** the change, **confirm**, **execute**, and
   **verify** by reading it back (e.g. `forge pr view N -o json | jq '{state, labels, milestone}'`).

## Everyday commands

| Task | Command |
|---|---|
| PR for current branch | `forge pr view -o json \| jq '{number,state,draft,head:.head.ref,base:.base.ref}'` |
| List PRs / issues | `forge pr list -s open -L 50` · `forge issue list -a <login> -s open` |
| PR diff / checkout | `forge pr diff N` · `forge pr checkout N` |
| Create PR | `forge pr create -t "feat(x): …" -b "$(cat /tmp/body.md)" -B develop -H feature/x -l feature -l docs -m <milestone-number> -r alice [-d] [--push]` |
| Comment | `forge pr comment N -b "…"` · `forge issue comment N -b "…"` |
| Review | `forge pr review approve N -b "…"` · `forge pr review reject N -b "…"` · `forge pr review list N` |
| Merge | `forge pr merge N -m merge -d --commit-title "…" --commit-message "…"` (`-m squash\|rebase`) |
| Labels / milestones | `forge label list -o json` · `forge milestone list -s open -o json` · `forge issue edit N -m <number>` |
| CI | `forge ci list -b <branch> -L 10` · `forge ci view RUN` (lists job IDs) · `forge ci log JOB` · `forge ci retry RUN` · `forge ci run <workflow> -b main -F key=val` |
| Releases | `forge release list` · `forge release create --tag v1.2.0 -t "v1.2.0" -b "…" [--draft] [--generate-notes]` |
| Raw API | `forge api 'repos/{owner}/{repo}/pulls/N/comments' \| jq …` · `scripts/api-pages.sh '<endpoint>'` |

Milestones: GitHub needs the **number** (titles are silently ignored), Gitea/Forgejo accept
title or ID, GitLab ignores `-m` in 0.10.1 (use the API) — look numbers up with
`forge milestone list -o json` and read the PR back after setting.
`forge pr edit -l` *replaces* the label set; include existing labels when adding one.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/forge-ctx.sh [-n] [-r remote] [-C dir]` | read-only pre-flight: remote/host/slug, token presence, API repo, current PR, rate limit; exit 3 = no token |
| `scripts/api-pages.sh [-p per-page] [-m max-pages] [-R owner/repo] <endpoint>` | GET all pages of a list endpoint as one JSON array |
