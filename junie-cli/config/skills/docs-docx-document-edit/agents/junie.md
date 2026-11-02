# Junie Tuning: docs-docx-document-edit

## Tool usage

- Use `bash` to run `soffice`, `pdftoppm`, and `scripts/render_docx.py`; these are not covered by the specialized search/edit tools.
- Use the image-viewing capability of the `open` tool on the rendered PNG pages to visually inspect layout, rather than trying to infer layout from raw XML or text extraction.
- Edit `.docx` content through a small Python script invoked via `bash` (using `python-docx`), not by hand-editing the underlying XML/zip structure.
- Do not use `open_entire_file` on `.docx` files; they are binary containers and will not render as useful text.

## Context window

- Keep the render/inspect loop tight: render only the pages that changed when possible, instead of re-rendering the whole document after every minor edit.
- Summarize what changed in the document instead of pasting full `python-docx` scripts back into the conversation once they've run successfully.

## Workflow notes

- All intermediate PDFs/PNGs must go under `/tmp` (see the global scratch-directory convention); never commit render artifacts to the project repo.
- If `soffice`/`poppler-utils` are missing, install them via the project's package manager (per [SETUP] mode conventions) before falling back to text-only extraction.
- Ask for explicit user confirmation before installing system packages if the environment restricts package installation.
