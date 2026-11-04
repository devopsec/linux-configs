---
name: gfx-slack-gif-create
description: Knowledge and utilities for creating animated GIFs optimized for Slack. Provides constraints, validation tools, and animation concepts. Use when users request animated GIFs for Slack, e.g. "make me a GIF of X doing Y for Slack" or "create a Slack emoji GIF of ...".
---

# GFX Slack GIF Create

## Overview

Build Slack-optimized animated GIFs by generating frames with PIL and assembling them with the bundled `scripts/core` utilities. This skill provides knowledge (Slack's constraints, animation concepts) and small helpers (GIF assembly, validation, easing, frame composition) — not pre-made animation templates or a graphics library.

## Dependencies

Check first, then ask the user to install if missing (do not install without confirmation):

```bash
python3 -c "import PIL, imageio, numpy" 2>/dev/null && echo OK || echo MISSING
```

If missing, ask the user to run (prefer `uv`, fall back to `pip` only if `uv` is unavailable):

```bash
uv pip install pillow imageio numpy
```

## Slack Requirements

**Dimensions:**
- Emoji GIFs: 128x128 (recommended)
- Message GIFs: 480x480

**Parameters:**
- FPS: 10-30 (lower is smaller file size)
- Colors: 48-128 (fewer = smaller file size)
- Duration: keep under 3 seconds for emoji GIFs

## Core Workflow

```python
from core.gif_builder import GIFBuilder
from PIL import Image, ImageDraw

# 1. Create builder
builder = GIFBuilder(width=128, height=128, fps=10)

# 2. Generate frames
for i in range(12):
    frame = Image.new('RGB', (128, 128), (240, 248, 255))
    draw = ImageDraw.Draw(frame)
    # Draw your animation using PIL primitives
    # (circles, polygons, lines, etc.)
    builder.add_frame(frame)

# 3. Save with optimization
builder.save('output.gif', num_colors=48, optimize_for_emoji=True)
```

Save output GIFs to a scratch/temp directory unless the user asks to keep them in the project.

## Drawing Graphics

### Working with user-uploaded images

If a user uploads an image, consider whether they want to:
- **Use it directly** (e.g., "animate this", "split this into frames")
- **Use it as inspiration** (e.g., "make something like this")

```python
from PIL import Image
uploaded = Image.open('file.png')
# Use directly, or just as reference for colors/style
```

### Drawing from scratch

Use PIL `ImageDraw` primitives — circles/ovals (`draw.ellipse`), polygons/stars/triangles (`draw.polygon`), lines (`draw.line`), rectangles (`draw.rectangle`).

**Don't use:** emoji fonts (unreliable across platforms) or assume pre-packaged graphics exist in this skill.

### Making graphics look good

- **Thicker lines**: always `width=2` or higher for outlines/lines; `width=1` looks choppy.
- **Visual depth**: gradients for backgrounds (`create_gradient_background`), layered shapes for complexity.
- **Interesting shapes**: add highlights/rings/patterns instead of plain shapes; combine shapes (stars + sparkles, circles + rings).
- **Colors**: vibrant, complementary colors; contrast outlines vs. fills; consider overall composition.
- **Complex shapes** (hearts, snowflakes, etc.): combine polygons and ellipses, calculate points for symmetry, add details.

Be creative and detailed — a good Slack GIF should look polished, not like placeholder graphics.

## Available Utilities (`scripts/core`)

Run scripts with `scripts/` on the Python path (e.g. `PYTHONPATH=scripts python3 ...`), or copy/import `core` from the skill's `scripts/` directory into a working script.

### GIFBuilder (`core.gif_builder`)

Assembles frames and optimizes for Slack:

```python
builder = GIFBuilder(width=128, height=128, fps=10)
builder.add_frame(frame)          # Add PIL Image
builder.add_frames(frames)        # Add list of frames
builder.save('out.gif', num_colors=48, optimize_for_emoji=True, remove_duplicates=True)
```

### Validators (`core.validators`)

Check if a GIF meets Slack requirements:

```python
from core.validators import validate_gif, is_slack_ready

passes, info = validate_gif('my.gif', is_emoji=True, verbose=True)
if is_slack_ready('my.gif'):
    print("Ready!")
```

### Easing Functions (`core.easing`)

Smooth motion instead of linear:

```python
from core.easing import interpolate

t = i / (num_frames - 1)  # progress 0.0 to 1.0
y = interpolate(start=0, end=400, t=t, easing='ease_out')
# Available: linear, ease_in, ease_out, ease_in_out,
# bounce_out, elastic_out, back_out (and more, see EASING_FUNCTIONS)
```

### Frame Helpers (`core.frame_composer`)

Convenience functions for common needs:

```python
from core.frame_composer import (
    create_blank_frame,          # Solid color background
    create_gradient_background,  # Vertical gradient
    draw_circle,                 # Helper for circles
    draw_text,                   # Simple text rendering
    draw_star,                   # 5-pointed star
)
```

## Animation Concepts

- **Shake/Vibrate**: offset position with `math.sin()`/`math.cos()` over frame index; add small random variation.
- **Pulse/Heartbeat**: scale size with `math.sin(t * frequency * 2 * math.pi)`; heartbeat = two quick pulses then pause; scale 0.8-1.2.
- **Bounce**: `interpolate()` with `easing='bounce_out'` for landing, `easing='ease_in'` for the accelerating fall; apply gravity by increasing y velocity each frame.
- **Spin/Rotate**: `image.rotate(angle, resample=Image.BICUBIC)`; use a sine wave for angle instead of linear for a wobble.
- **Fade In/Out**: RGBA image with alpha channel adjustment, or `Image.blend(image1, image2, alpha)`.
- **Slide**: start outside frame bounds, `interpolate()` with `easing='ease_out'` (or `'back_out'` for overshoot).
- **Zoom**: scale from 0.1-2.0 and crop center (zoom in) or 2.0-1.0 (zoom out); optional motion blur for drama.
- **Explode/Particle burst**: particles with random angles/velocities; `x += vx`, `y += vy`, `vy += gravity_constant`; fade out over time.

## Optimization Strategies

Only when asked to make the file smaller, apply a few of:

1. **Fewer frames** — lower FPS (10 instead of 20) or shorter duration
2. **Fewer colors** — `num_colors=48` instead of 128
3. **Smaller dimensions** — 128x128 instead of 480x480
4. **Remove duplicates** — `remove_duplicates=True` in `save()`
5. **Emoji mode** — `optimize_for_emoji=True` auto-optimizes

```python
builder.save(
    'emoji.gif',
    num_colors=48,
    optimize_for_emoji=True,
    remove_duplicates=True,
)
```

## Philosophy

This skill provides:
- **Knowledge**: Slack's requirements and animation concepts
- **Utilities**: `GIFBuilder`, validators, easing functions, frame helpers
- **Flexibility**: create the animation logic yourself using PIL primitives

It does NOT provide:
- Rigid animation templates or pre-made functions
- Emoji font rendering (unreliable across platforms)
- A library of pre-packaged graphics

Be creative! Combine concepts (bouncing + rotating, pulsing + sliding, etc.) and use PIL's full capabilities.

## Agent-specific notes

See `agents/junie.md` and `agents/claude.md` for tool-specific tuning.

## Source

Adapted from the `slack-gif-creator` skill in [JetBrains/skills](https://github.com/JetBrains/skills/blob/e0f258b5cfed145015cb3e48da9a97947f7c4ed7/slack-gif-creator/SKILL.md) (originally authored by Anthropic, Apache-2.0 licensed; see `LICENSE.txt`). The bundled `core` utilities (`gif_builder.py`, `validators.py`, `easing.py`, `frame_composer.py`) are carried over unchanged in logic, just reformatted.
