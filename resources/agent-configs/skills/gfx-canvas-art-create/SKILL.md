---
name: gfx-canvas-art-create
description: Create original static visual artwork (poster, art piece, design) as .pdf/.png files by first defining a visual design philosophy, then expressing it on a canvas with expert-level craftsmanship. Use when the user asks for a poster, piece of art, visual design, or other static visual artifact. Never copy existing artists' work.
metadata:
  short-description: "Create static visual artwork"
  original-author: Anthropic
  source: https://github.com/anthropics/skills/tree/main/skills/canvas-design
  imported-via-audit: true
license: See assets/canvas-fonts/*-OFL.txt for bundled font licenses (SIL Open Font License).
---

# Canvas Art Creator

## Overview

Produces original visual art (poster/design/static piece) as `.md` (philosophy) + `.pdf`/`.png` (artifact) outputs. The work is done in two passes: first define an aesthetic movement in words, then express it almost entirely through visual composition — never through decorated documents.

## Workflow

1. **Create a visual design philosophy** (`.md` file)
   - Name the movement (1-2 words), e.g. "Brutalist Joy", "Chromatic Silence".
   - Write 4-6 paragraphs describing how it manifests through space/form, color/material, scale/rhythm, composition/balance, visual hierarchy.
   - Treat any user input as a foundation only — it must not constrain creative freedom.
   - Repeatedly stress craftsmanship in the philosophy itself (see Guidelines below).
   - See `references/philosophy-examples.md` for condensed reference examples before writing a new one.
2. **Deduce the subtle reference**
   - Identify a subtle, sophisticated conceptual thread from the original request and weave it invisibly into form/color/composition — never literal, never announced. Someone familiar with the topic should feel it intuitively; everyone else should just see a masterful abstract composition.
3. **Express the philosophy on a canvas** (`.pdf` or `.png`)
   - Single page, highly visual, design-forward, unless multiple pages are requested (see Multi-Page Option).
   - Text is minimal, visual-first, and contextual (whisper-quiet labels vs. bold typographic gestures depending on the piece).
   - Use fonts from `assets/canvas-fonts/` — pick different fonts per project; make typography part of the art itself rather than plain digital typesetting.
   - Nothing overlaps, nothing falls off the canvas; every element has proper margins and breathing room.
4. **Refine** — take a second pass: don't add graphics, make the existing composition tighter, crisper, more cohesive. If tempted to add a new shape/function, stop and instead ask how to make what's already there more resolved.
5. **Multi-page option** (only if requested) — add creative variations on the same philosophy, distinctly different from each other, bundled into the same `.pdf` or as multiple `.png`s, as if pages from the same coffee-table book.

## Guidelines

- Output only `.md`, `.pdf`, and `.png` files.
- Information lives in design (space, color, composition), not in paragraphs — avoid explanatory text blocks.
- Repeatedly emphasize expert craftsmanship in the philosophy: the final work must look meticulously crafted, labored over with care, the product of someone at the top of their field ("meticulously crafted", "painstaking attention", "master-level execution").
- Keep the philosophy generic (not tied to the specific request) so it stays reusable, while still being specific enough to guide a distinct aesthetic direction.
- Avoid redundancy: mention each design aspect (color, spatial relationships, typography) once unless adding new depth.
- Never copy an existing artist's work — create original visual designs to avoid copyright violations.
- Keep content sophisticated even for playful/fictional topics (movie, game, book) — never cartoony or amateur.

## Resources

- `references/philosophy-examples.md` — condensed example philosophies ("Concrete Poetry", "Chromatic Language", "Analog Meditation", "Organic Systems", "Geometric Silence") to calibrate tone and structure before writing a new one.
- `assets/canvas-fonts/` — bundled font families (`.ttf`) with their SIL Open Font License files, for use as typography in the generated canvas.
