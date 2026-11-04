# Audit Report: web-playwright-browser-automate

- **Source (pre-install path):** `/home/anon/.junie/skills/web-playwright-browser-automate`
- **Audited at:** 2026-09-16 17:01:17 UTC
- **Trust classification:** UNTRUSTED (not authored by this agent/workflow)

## Threat Analysis

No critical red-flag patterns were detected by automated scanning.

**Warnings (non-critical, still review manually):**
- Potential hardcoded credential 'password' detected in SKILL.md.

## Code Analysis

- **Files reviewed (3):**
  - `SKILL.md`
  - `references/workflows.md`
  - `references/cli.md`
- **Executable files:** None
- **Inline commands found in SKILL.md:** 20
  - `SKILL.md: command -v playwright-cli >/dev/null 2>&1`
  - `SKILL.md: npm install -g @playwright/cli@latest`
  - `SKILL.md: playwright-cli --help`
  - `SKILL.md: playwright-cli open https://example.com`
  - `SKILL.md: playwright-cli snapshot`
  - `SKILL.md: playwright-cli click e3`
  - `SKILL.md: playwright-cli snapshot`
  - `SKILL.md: playwright-cli open https://example.com/form`
  - `SKILL.md: playwright-cli snapshot`
  - `SKILL.md: playwright-cli fill e1 "user@example.com"`
  - `SKILL.md: playwright-cli fill e2 "<password>"`
  - `SKILL.md: playwright-cli click e3`
  - `SKILL.md: playwright-cli snapshot`
  - `SKILL.md: playwright-cli open https://example.com --headed`
  - `SKILL.md: playwright-cli tracing-start`
  - `SKILL.md: playwright-cli tracing-stop`
  - `SKILL.md: playwright-cli tab-new https://example.com`
  - `SKILL.md: playwright-cli tab-list`
  - `SKILL.md: playwright-cli tab-select 0`
  - `SKILL.md: playwright-cli snapshot`

## Permission Scope

- **Network calls:** SKILL.md: https://example.com, SKILL.md: https://example.com/form, SKILL.md: https://example.com, SKILL.md: https://example.com, SKILL.md: https://github.com/JetBrains/skills/blob/e0f258b5cfed145015cb3e48da9a97947f7c4ed7/playwright/SKILL.md), references/workflows.md: https://demo.playwright.dev/todomvc, references/workflows.md: https://example.com, references/cli.md: https://example.com, references/cli.md: https://example.com/page, references/cli.md: https://demo.playwright.dev/todomvc, references/cli.md: https://demo.playwright.dev/todomvc

## Risk Classification

- **Risk level:** MEDIUM
- **Verdict:** FULL REVIEW REQUIRED

## Validation Results

- **Structural/naming validation:** PASS
- **Message:** Skill validation completed successfully.
- **Critical findings:** 0
- **Warnings:** 1
- **junie documentation present:** yes
- **claude documentation present:** yes

## Required Next Steps

1. Show this AUDIT.md to the user in full.
2. Get explicit approve/reject decision from the user. If areas of concern remain,
   start an interactive investigation of those specific files before deciding.
3. If **rejected**: run `audit_skill.py <path> --archive-rejected` (do not install; do not delete).
4. If **approved**: proceed to the mandatory final human review of the finished skill
   (all files, not just the flagged ones) before it is copied into the skills directory.
5. No skill — self-authored or imported — is installed without that final human sign-off.
