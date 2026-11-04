# Claude Code Tuning: gfx-slack-gif-create

## Style

- Keep animation code creative but concise: prefer composing the bundled helpers (`GIFBuilder`, `interpolate`, `draw_*`, `create_gradient_background`) over reimplementing basic drawing/easing logic from scratch.
- Favor a short, readable frame-generation loop over one giant unrolled script.

## Commands

- Dependency check: `python3 -c "import PIL, imageio, numpy"`
- Core loop: build frames with `PIL.ImageDraw` + `core.frame_composer`/`core.easing` helpers -> `GIFBuilder.add_frame()` -> `GIFBuilder.save(...)`
- Validate: `core.validators.validate_gif(...)` / `is_slack_ready(...)`

## Safety

- If the dependency check fails, stop and surface the `uv pip install pillow imageio numpy` instruction from `SKILL.md` to the user; do not install packages yourself without confirmation.
- Do not fabricate pre-packaged graphics or emoji fonts — draw everything with PIL primitives per the skill's philosophy.
