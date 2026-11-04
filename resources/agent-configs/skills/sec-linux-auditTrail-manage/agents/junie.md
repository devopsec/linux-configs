# Junie CLI Specifics for Sec Linux Audittrail Manage

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI branches and inspect the host's actual logging stack before suggesting rules.
- Keep retention and destination values in approved configuration; avoid collecting unnecessary personal data.
- Preserve evidence before altering a suspect host or its logs.

## Instructions Overrides
- Do not alter production audit rules or delete evidence without explicit approval.

## Performance Notes
- Load only the relevant journald, auditd, or forwarding section.
