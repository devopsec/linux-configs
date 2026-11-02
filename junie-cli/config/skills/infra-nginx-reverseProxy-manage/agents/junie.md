# Junie CLI Specifics for Infra Nginx Reverseproxy Manage

## Context & Tuning
- Execute SAD KITTI config selection and load only the nginx or Traefik guidance needed.
- Use the configured proxy default unless the user selects another supported option.

## Instructions Overrides
- No commits; require approval before production reloads or TLS/access-policy changes.
- Redact secrets, private keys, and untrusted proxy/client details.
