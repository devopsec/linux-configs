# Junie CLI Specifics for Sec Ops Forensics Collect

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI order and review the collector before running it.
- Require an approved, separate evidence destination and read cloud bucket/resource identifiers from incident TOML or ask.
- Treat archives and custody records as sensitive; do not paste raw evidence into responses.

## Instructions Overrides
- Do not execute collection on a live host without explicit user/IC approval.

## Performance Notes
- Load only the collection section needed; preserve original evidence and analyze copies.
