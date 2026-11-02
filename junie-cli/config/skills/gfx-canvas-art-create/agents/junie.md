# Junie CLI Specifics for Gfx Canvas Art Create

## Context & Tuning

Junie CLI has no native canvas/drawing surface. Produce the `.pdf`/`.png` artifact by writing and running a short script (e.g. Python with `Pillow`/`reportlab`/`matplotlib`/`cairo`, or Node with a canvas/SVG-to-PDF library) via the terminal tool, then verify the output file exists and inspect it with the `open` tool (image/PDF preview) before declaring it done.

## Instructions Overrides

- Place generated font-rendering code and the output `.md`/`.pdf`/`.png` files under the current project (or the requested output directory) — never inside this skill folder.
- If a required font family is missing from `assets/canvas-fonts/`, fall back to another bundled family rather than downloading new fonts, unless the user explicitly allows network access.

## Performance Notes

- Prefer a single self-contained script over many small edits; iterate on the script and re-render rather than hand-editing a binary PDF/PNG.
- Keep the design-philosophy `.md` file short (4-6 paragraphs) so it stays fast to write and re-read between the two workflow steps.
