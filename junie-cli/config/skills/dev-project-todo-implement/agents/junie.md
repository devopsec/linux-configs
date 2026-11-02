# Junie specifics — dev-project-todo-implement

- Announce skill use once, then work silently through resolve → implement → doc update.
- Prefer specialized file tools over dumping tracker files via shell.
- Scratch extraction from DOCX/PDF under `/tmp/<task>/`; do not write scratch into the repo.
- Never `git commit`; offer a message draft and point at `vcs-git-commit-create` if the user wants a commit.
- Ask clarifying questions inline as a short numbered list (no multi-select UI).
