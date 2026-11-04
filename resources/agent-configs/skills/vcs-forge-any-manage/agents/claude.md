# Claude specifics — vcs-forge-any-manage

- Run `scripts/forge-ctx.sh` once per repo per session and keep the result; independent reads
  (`forge pr view -o json`, `forge ci list`, `api-pages.sh …`) can run in one turn.
- Every mutating forge call publishes to an external service: show the exact command and
  content and get explicit approval first — even when the user approved a similar call earlier.
- Keep the Bash working directory at the project root; target other repos with `-R owner/repo`
  rather than `cd`.
- Write bodies to a file with the Write tool and pass `-b "$(cat /tmp/x.md)"` — avoids shell
  quoting bugs with backticks and `$`.
- Authentication is the user's step: suggest `! forge auth login --domain <host> --token-cmd '…'`
  so it runs in their session. Never echo tokens or token-cmd strings.
- Unauthenticated GitHub reads are limited to 60/hour: check `forge rate-limit` before
  paginating large lists.
