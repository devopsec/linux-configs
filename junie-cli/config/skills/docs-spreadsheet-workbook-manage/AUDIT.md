# Audit Report: docs-spreadsheet-workbook-manage

- **Source (pre-install path):** `/home/anon/.junie/skills/docs-spreadsheet-workbook-manage`
- **Audited at:** 2026-09-16 17:42:20 UTC
- **Trust classification:** UNTRUSTED (not authored by this agent/workflow)

## Threat Analysis

No critical red-flag patterns were detected by automated scanning.

## Code Analysis

- **Files reviewed (1):**
  - `SKILL.md`
- **Executable files:** None
- **Inline commands found in SKILL.md:** 5
  - `SKILL.md: soffice --headless --convert-to pdf --outdir "$OUTDIR" "$INPUT_XLSX"`
  - `SKILL.md: pdftoppm -png "$OUTDIR/$BASENAME.pdf" "$OUTDIR/$BASENAME"`
  - `SKILL.md: uv pip install openpyxl pandas`
  - `SKILL.md: python3 -m pip install openpyxl pandas`
  - `SKILL.md: uv pip install matplotlib`

## Permission Scope

- **Network calls:** SKILL.md: https://github.com/JetBrains/skills/blob/e0f258b5cfed145015cb3e48da9a97947f7c4ed7/spreadsheet/SKILL.md)

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
