# Commit skill modes — edge cases

## message-only

- Empty diff → say so; do not invent a message from the conversation alone unless the user asks to message "what we just did" from chat context — then label it **from conversation, not from git**.
- Partial stage → describe staged vs unstaged clearly; offer two messages if both are dirty and unrelated.
- Binary-only changes → still draft a subject from paths (`assets`, `vendor`); note binaries in body.
- Huge diffs → summarize by path groups; do not paste the full diff into chat.

## commit

- Hooks fail → show hook output; do not `--no-verify` unless the user explicitly orders it.
- Nothing to commit → stop after status.
- Merge conflicts → do not commit; help resolve first only if asked.
- Partial approval → stage only the approved paths.
- Sign-off / GPG → only if the repo already requires it and the user asks; never invent signing keys.

## split-plan

- Keep dependency order (e.g. types/schema before callers).
- Tests travel with the behavior they lock unless user wants a pure `test` commit.
- Docs-only follow-ups can be a final `docs` commit.
- If everything is one concern, say so — do not force artificial splits.

## amend

- Safe: tip commit not pushed; adding forgotten files or fixing the message the user just made.
- Unsafe without explicit accept: commit reachable from a shared remote tracking branch.
- Prefer `git commit --amend --no-edit` only when the message stays correct and only files change.
- Never amend someone else's commit.

## Mode selection tie-breakers

| Phrase | Mode |
|--------|------|
| "draft/propose/write a commit message" | message-only |
| "commit these changes" / "make a commit" | commit (after approval) |
| "don't touch git" / "message only" | message-only |
| "split commits" / "atomic commits" | split-plan |
| "amend" / "fix last commit message" | amend |

If still ambiguous → **message-only** + one clarifying question.
