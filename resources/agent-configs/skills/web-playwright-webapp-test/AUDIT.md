# Audit Report: web-playwright-webapp-test

- **Source (pre-install path):** `/home/anon/.junie/skills/web-playwright-webapp-test`
- **Audited at:** 2026-09-16 22:50:57 UTC
- **Trust classification:** UNTRUSTED (not authored by this agent/workflow)

## Threat Analysis

No critical red-flag patterns were detected by automated scanning.

## Code Analysis

- **Files reviewed (2):**
  - `SKILL.md`
  - `scripts/with_server.py`
- **Executable files:** `scripts/with_server.py`
- **Inline commands found in SKILL.md:** 10
  - `SKILL.md: python3 scripts/with_server.py --help`
  - `SKILL.md: python3 scripts/with_server.py --server "npm run dev" --port 5173 -- python3 your_automation.py`
  - `SKILL.md: python3 scripts/with_server.py \`
  - `SKILL.md: --server "cd backend && python3 server.py" --port 3000 \`
  - `SKILL.md: --server "cd frontend && npm run dev" --port 5173 \`
  - `SKILL.md: -- python3 your_automation.py`
  - `SKILL.md: uv pip install playwright`
  - `SKILL.md: python3 -m playwright install chromium`
  - `SKILL.md: python3 -m pip install playwright`
  - `SKILL.md: python3 -m playwright install chromium`

## Permission Scope

- **Network calls:** SKILL.md: http://localhost:5173, SKILL.md: https://github.com/JetBrains/skills/blob/e0f258b5cfed145015cb3e48da9a97947f7c4ed7/webapp-testing/SKILL.md)

## Risk Classification

- **Risk level:** MEDIUM
- **Verdict:** FULL REVIEW REQUIRED

## Validation Results

- **Structural/naming validation:** PASS
- **Message:** Skill validation completed successfully.
- **Critical findings:** 0
- **Warnings:** 0
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
