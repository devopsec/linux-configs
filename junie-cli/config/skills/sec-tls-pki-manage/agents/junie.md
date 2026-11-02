# Junie CLI Specifics for Sec Tls Pki Manage

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI load order and inspect the actual certificate request and issuer requirements.
- Use installed cryptographic tools; do not assume a CA vendor, key algorithm, or trust path without evidence.
- Keep private keys and passphrases out of workspace output, logs, and chat.

## Instructions Overrides
- Ask before creating keys, submitting CSRs, or revoking production certificates.

## Performance Notes
- Load only the PKI procedure relevant to issuance, validation, or trust changes.
