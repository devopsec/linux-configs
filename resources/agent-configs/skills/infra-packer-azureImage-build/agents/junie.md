# Junie specifics — infra-packer-azureImage-build

- Follow the skill `SKILL.md` workflow; load `references/` only as needed.
- Scratch outputs under `/tmp`; do not pollute the project with temp files.
- Packer builds can create billable cloud resources — confirm before `packer build`.
- Never print cloud secrets; prefer env/role credentials already configured.
- No git commits unless the user explicitly requests `vcs-git-commit-create`.
