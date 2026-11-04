# Claude Specifics for Sec Vault Secrets Manage

## Operating notes

- Follow the SAD KITTI branch and load only Vault sections relevant to the user request.
- Redact tokens and recovery material; report policy paths and status rather than secret contents.
- Obtain explicit operator confirmation before irreversible or cluster-wide actions.
