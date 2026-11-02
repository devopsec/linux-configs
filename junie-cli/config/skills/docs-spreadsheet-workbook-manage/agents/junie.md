# Junie Tuning: docs-spreadsheet-workbook-manage

## Tool usage

- Prefer specialized tools (`open`, `search_replace`, `create`) for reading/editing plain-text `.csv`/`.tsv` files; use `bash` to run `openpyxl`/`pandas` scripts for `.xlsx` since binary spreadsheets can't be edited directly with the text-editing tools.
- Check for `openpyxl`/`pandas` availability first (`python3 -c "import openpyxl, pandas"`); only propose an install command if the check fails, and confirm with the user before installing anything.
- Use `open` to view rendered PNGs after running the LibreOffice/Poppler rendering commands, instead of guessing layout from code alone.
- Load example scripts from `references/examples/openpyxl/` only when you need a concrete pattern; do not paste their full contents into the conversation.

## Context window

- Do not dump full workbook contents (e.g. every row of a large sheet) into the conversation; summarize shape, headers, and a few sample rows instead.
- Read only the specific example script needed (`create_basic_spreadsheet.py`, `create_spreadsheet_with_styling.py`, `read_existing_spreadsheet.py`, or `styling_spreadsheet.py`), not all four at once.

## Workflow notes

- Keep intermediate/scratch files under `/tmp` (or the session scratch directory) unless the user's final deliverable path is inside the project.
- Never overwrite an existing formatted workbook's styling unless the user explicitly asks for a redesign; render and inspect it first.
- If rendering tools (`soffice`, `pdftoppm`) are unavailable, say so plainly and tell the user to review layout locally instead of skipping the check silently.
