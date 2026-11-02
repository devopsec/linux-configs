# Claude Specifics for Sec Sip Tls Manage

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI load order and consult the Kamailio platform skill only for Kamailio endpoints.
- Inspect configured certificate paths and peer requirements before suggesting reload or trust changes.
- Keep peer names and credential values in approved configuration; never expose private keys.

## Instructions Overrides
- Require explicit approval before changing a production SIP listener or trust policy.

## Performance Notes
- Load only the certificate layout or verification section needed for the current task.
