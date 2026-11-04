---
name: gfx-mcp-image-create
description: "Generate UI mockups, icons, logos, and local graphic assets via a local image-generation MCP server (e.g. LM Studio image-gen). Use when the user requests visual assets, background images, placeholder illustrations, icons, or UI mockups — not when they only want CSS/HTML drawings."
compatibility:
  - jetbrains-ai-assistant
  - lm-studio-mcp
---

# MCP image generation

Route image requests through the configured **local** image MCP tool. Do not hallucinate binary assets.

## When to use

- Explicit image/asset generation (PNG/WebP/SVG raster via model)
- Mockups to drop into `src/assets/`, `public/`, or design folders

**Not** for: pure CSS art, SVG hand-authored icons (prefer code), or remote DALL·E/Gemini unless the user names that API.

## Workflow

1. **Confirm target path** — project folder for the asset (default `src/assets/` or existing media dir).
2. **Call MCP** — use the image-generation tool exposed by the local MCP server (commonly named `image-gen` or similar). Pass a clear `prompt` and aspect ratio/size if supported.
3. **Wait** for the tool payload (path or bytes reference). Do not edit the tree until the call returns.
4. **Place file** — copy/move into the target folder with a stable kebab-case name.
5. **Wire up** — update `<img>`, CSS `url()`, or imports to the new path.
6. **Report** — path, prompt used, and any size/format notes.

## Failures

| Problem | Action |
|---------|--------|
| MCP not connected | Tell the user; stop. Do not invent an image. |
| OOM / timeout | Report; suggest smaller size or simpler prompt. |
| Wrong tool schema | Read tool descriptor; adapt params — do not call external HTTP APIs. |

## Guardrails

- Prefer local MCP over cloud image APIs unless the user explicitly requests otherwise.
- Do not commit generated binaries unless the user asks.
- Keep prompts free of secrets and private customer data.
