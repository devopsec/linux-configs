# Junie CLI Specifics for Sec Tls Config Audit

## Context & Tuning
- Follow `SKILL.md`'s config hook and use only the configured/default probe against an authorized target.
- Read approved target and policy values from TOML or ask; never infer a host, range, or SNI name.
- Inspect endpoint results and native configuration tests before proposing changes.

## Instructions Overrides
- Do not perform active probes or production configuration changes without approval.

## Performance Notes
- Prefer the smallest endpoint sample and load only the relevant configuration section.
