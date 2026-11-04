# Junie specifics — vcs-gcli-any-manage

- Execute the SKILL.md `sadkitti` routing block literally; load only the references it selects.
- The terminal tool is not a TTY: gcli submits every write without asking. Ask inline
  (numbered list) and get approval of command, target repo, and message *before* running it.
- Write message bodies to `/tmp/*.md` and use `scripts/gcli-msg.sh`; never let gcli open an
  editor (it would hang the terminal tool).
- Avoid `monitor`, `review`, `edit`, and `open` actions (interactive / TTY / browser).
- Don't open or print `~/.config/gcli/config` (plaintext tokens).
- No commits; no force pushes.
