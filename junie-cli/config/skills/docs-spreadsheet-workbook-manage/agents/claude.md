# Claude Code Tuning: docs-spreadsheet-workbook-manage

## Style

- Keep instructions concise and imperative: confirm goal, pick tool (`openpyxl` vs `pandas`), write formulas not hardcoded values, render, review, save.
- Run one script or command at a time and inspect its output/rendered PNGs before making further edits, rather than batching many workbook changes blind.

## Commands

- Dependency check: `python3 -c "import openpyxl, pandas"`
- Render for review: `soffice --headless --convert-to pdf --outdir "$OUTDIR" "$INPUT_XLSX"` then `pdftoppm -png "$OUTDIR/$BASENAME.pdf" "$OUTDIR/$BASENAME"`
- See `references/examples/openpyxl/` for runnable create/read/style examples.

## Safety

- If `openpyxl`/`pandas`/rendering tools are missing, tell the user what's missing and how to install it themselves; do not silently `sudo`-install system packages.
- Preserve existing formulas and formatting in provided workbooks; never silently replace formulas with hardcoded values.
