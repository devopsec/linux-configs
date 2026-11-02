---
name: docs-docx-document-edit
description: Use when the task involves reading, creating, or editing .docx documents, especially when formatting or layout fidelity matters (tables, diagrams, pagination, styles). Prefer python-docx for structured edits plus a rendered visual check (DOCX -> PDF -> PNG) before delivery.
---

# Docs Docx Document Edit

## Overview

Read, create, or edit Word `.docx` documents with professional formatting, validating layout visually whenever possible instead of relying on text extraction alone.

## Workflow

1. **Prefer visual review** when layout matters (tables, diagrams, pagination):
   - If `soffice` and `pdftoppm` are available, convert DOCX -> PDF -> PNGs (see commands below).
   - Or use `scripts/render_docx.py` (requires `pdf2image` and Poppler).
   - If these tools are missing, install them (see Dependencies) or ask the user to review rendered pages locally.
2. **Edit with `python-docx`** for structured creation/edits (headings, styles, tables, lists) rather than manual XML manipulation.
3. **Re-render after each meaningful change** and inspect the pages before continuing.
4. **Fallback**: if visual review is not possible, extract text with `python-docx` and explicitly call out the layout risk to the user.
5. **Clean up**: keep intermediate render outputs organized in a temp location and delete them once approved.

## Temp and output conventions

- Use a scratch/temp directory for intermediate render files (e.g. PDF/PNG previews); delete when done.
- Keep filenames stable and descriptive; do not leave render artifacts in the repository.

## Dependencies (install if missing)

Prefer `uv` for Python dependency management:

```bash
uv pip install python-docx pdf2image
```

If `uv` is unavailable:

```bash
python3 -m pip install python-docx pdf2image
```

System tools (for rendering DOCX -> PDF -> PNG): `libreoffice` (provides `soffice`) and `poppler-utils` (provides `pdftoppm`).

Do not install system packages yourself without explicit user confirmation, since this typically requires elevated privileges. Instead, tell the user which packages are missing (`libreoffice`, `poppler-utils` on Ubuntu/Debian; `libreoffice`, `poppler` via Homebrew on macOS) and ask them to install these, or to confirm before you run the install command.

## Rendering commands

DOCX -> PDF:

```bash
soffice -env:UserInstallation=file:///tmp/lo_profile_$$ --headless --convert-to pdf --outdir "$OUTDIR" "$INPUT_DOCX"
```

PDF -> PNGs:

```bash
pdftoppm -png "$OUTDIR/$BASENAME.pdf" "$OUTDIR/$BASENAME"
```

Bundled helper (wraps both steps):

```bash
python3 scripts/render_docx.py /path/to/file.docx --output_dir /tmp/docx_pages
```

## Quality expectations

- Deliver a client-ready document: consistent typography, spacing, margins, and clear hierarchy.
- Avoid formatting defects: clipped/overlapping text, broken tables, unreadable characters, or default-template styling.
- Charts, tables, and visuals must be legible in rendered pages with correct alignment.
- Use ASCII hyphens only. Avoid U+2011 (non-breaking hyphen) and other Unicode dashes.
- Citations and references must be human-readable; never leave leftover tool markers or placeholder strings.

## Final checks

- Re-render and inspect every page at 100% zoom before final delivery.
- Fix any spacing, alignment, or pagination issues and repeat the render loop.
- Confirm there are no leftovers (temp files, duplicate renders) unless the user asked to keep them.

## Agent-specific notes

See `agents/junie.md` and `agents/claude.md` for tool-specific tuning.

## Source

Adapted from the `doc` skill in [JetBrains/skills](https://github.com/JetBrains/skills/blob/e0f258b5cfed145015cb3e48da9a97947f7c4ed7/doc/SKILL.md) (originally authored by OpenAI, Apache-2.0 licensed).
