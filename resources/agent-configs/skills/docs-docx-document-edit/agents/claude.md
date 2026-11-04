# Claude Code Tuning: docs-docx-document-edit

## Style

- Keep instructions concise and imperative: convert, inspect, edit, re-render, confirm.
- Prefer a single self-contained Python script per edit session (using `python-docx`) over many small incremental tool calls.

## Commands

- Convert: `soffice -env:UserInstallation=file:///tmp/lo_profile_$$ --headless --convert-to pdf --outdir $OUTDIR $INPUT_DOCX`
- Render: `pdftoppm -png $OUTDIR/$BASENAME.pdf $OUTDIR/$BASENAME`
- Or use the bundled helper: `python3 scripts/render_docx.py <file.docx> --output_dir /tmp/docx_pages`

## Safety

- Review generated `python-docx` code before executing it, especially when it deletes or overwrites existing document content.
- Avoid loops re-rendering the same unchanged document; stop once a page is visually confirmed correct.
