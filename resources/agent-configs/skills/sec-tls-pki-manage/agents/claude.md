# Claude Specifics for Sec Tls Pki Manage

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI load order and inspect the certificate request and issuer requirements.
- Use tools available in the workspace; do not assume a CA vendor, key algorithm, or trust path.
- Keep private keys and passphrases out of workspace output, logs, and chat.

## Instructions Overrides
- Ask before creating keys, submitting CSRs, or revoking production certificates.

## Performance Notes
- Load only the PKI procedure relevant to issuance, validation, or trust changes.
