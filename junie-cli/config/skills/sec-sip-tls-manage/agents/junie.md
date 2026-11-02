# Junie CLI Specifics for Sec Sip Tls Manage

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI load order; use the Kamailio platform skill only when the endpoint uses Kamailio.
- Inspect configured certificate paths and peer requirements before suggesting a reload or trust change.
- Keep peer names and credential values in approved configuration; never expose private keys.

## Instructions Overrides
- Require explicit approval before changing a production SIP listener or trust policy.

## Performance Notes
- Load only the certificate layout or verification section needed for the current task.
