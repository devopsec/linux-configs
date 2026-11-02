# Junie CLI Specifics for Docs Ops Runbook Create

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI order and use repository source-of-truth files to ground each procedure.
- Keep site values as explained placeholders or approved TOML inputs; never write secrets into a runbook.
- Test on an approved non-production target and accurately record whether a procedure was tested or only reviewed.

## Instructions Overrides
- Do not execute an operational runbook while authoring it unless the user explicitly asks.

## Performance Notes
- Load only the template or review checklist needed for the current request.
