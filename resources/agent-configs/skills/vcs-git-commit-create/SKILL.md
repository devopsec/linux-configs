---
name: "vcs-git-commit-create"
description: "Git commit workflows using Conventional Commits: (1) message-only draft for staged/unstaged/all pending changes without touching git state, (2) stage and commit after explicit approval, (3) split multi-scope suggestions, (4) optional amend only when the user explicitly asks and policy allows. Use when asked to commit, draft a commit message, summarize staged/pending changes, or prepare conventional commit text. Never commit unless the user explicitly requests a commit."
---

# Git commit (multi-mode)

Conventional Commits helper with **explicit modes**. Default safety: **do not change git state** unless the user clearly asked to commit (or stage).

**Junie note:** Junie does not commit on its own. Always show the proposed message (and file list) for approval before any `git commit`. Never add a co-author trailer.

## Mode selection

| User intent | Mode | Git state changes? |
|-------------|------|--------------------|
| "commit message", "summarize pending/staged changes", "draft a commit" | **message-only** | **No** |
| "commit this", "stage and commit", "save a commit" | **commit** | Yes, after approval |
| "split into commits", "multiple commits" | **split-plan** | No (plan only) until user approves each |
| "amend the last commit" | **amend** | Only if explicitly requested and safe |

If ambiguous, prefer **message-only** and ask before staging/committing.

## Prepare (all modes)

```bash
git status --short
git log --oneline -8
git diff --cached          # staged
git diff                   # unstaged (message-only / split may need both)
git rev-parse --abbrev-ref HEAD
```

Mirror the project's tone and scope naming from recent commits and any `AGENTS.md` / `CONTRIBUTING.md` conventions.

**Diff scope for message-only:**

- User said **staged** → `--cached` only  
- User said **pending / unstaged / working tree** → unstaged or both  
- Unspecified → prefer staged if non-empty; else all pending; state which you used  

## Mode: message-only

1. Gather diffs per scope above.  
2. Draft Conventional Commit subject (+ body if needed).  
3. Show: mode, branch, file list summary, full message.  
4. **Stop.** Do not `git add`, `git commit`, `git reset`, or rewrite history.

## Mode: commit

1. Draft message (same rules as message-only).  
2. Present **staged file list** + message; if nothing staged, list what you propose to stage and wait for approval.  
3. On approval:

```bash
git add <approved-files>   # only if user agreed to stage
git commit -m "$(cat <<'EOF'
type(scope): subject

optional body
EOF
)"
```

4. Show `git status -sb` after.  
5. Never `--force`, never push unless user explicitly asks in the same turn.

## Mode: split-plan

When the diff mixes unrelated concerns:

1. Group files by concern.  
2. Propose an ordered list of commits (type/scope/subject + file set each).  
3. Wait; then run **commit** mode per group only as the user approves.

## Mode: amend

Only when user explicitly wants amend **and**:

- HEAD was created by the user in this branch context, and  
- commit is **not** pushed to a shared remote (check `@{upstream}` / status), or user explicitly accepts rewrite  

```bash
git commit --amend -m "..."
# or --amend --no-edit when only adding staged files the user approved
```

Refuse amend on pushed shared history unless the user insists after a clear warning.

## Project conventions

- Scope is **required** (kebab-case): `validation`, `auth`, `api`, …  
- Extra type: `security` (hardening / vuln fixes)  
- Subject: present-tense imperative, **≤50 chars**, **no** trailing period  
- **NEVER** generic subjects ("update code", "fix bug", "changes")  
- **NEVER** commit without explicit approval  
- **NEVER** include a co-author trailer — the user owns the commit  
- Prefer HEREDOC for multi-line messages  

## Message quality checklist

- [ ] One logical change per commit (or split-plan offered)  
- [ ] Type/scope match project history  
- [ ] Body explains *why* when non-obvious  
- [ ] No secret values in message  
- [ ] Correct mode (no accidental state change)

## References

- `references/commit_examples.md` — examples by type, good/bad  
- `references/modes.md` — extended mode edge cases  
