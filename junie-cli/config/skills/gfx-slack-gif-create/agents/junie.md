# Junie Tuning: gfx-slack-gif-create

## Tool usage

- Use `bash` to run the dependency check and any Python scripts that generate/validate GIFs; PIL/imageio drawing code is not covered by the specialized search/edit tools.
- Write generation scripts as standalone `.py` files (via `create`), then run them with `bash`, e.g. `PYTHONPATH=/home/anon/.junie/skills/gfx-slack-gif-create/scripts python3 /tmp/make_gif.py`.
- If the dependency check reports missing packages, stop and ask the user before running `uv pip install`.
- Use `open` on the resulting `.gif` to visually inspect it before declaring the task done, instead of trusting the code alone.

## Context window

- Load `scripts/core/*.py` only when writing the generation script; you don't need to paste their contents back into the conversation, just import from them.
- Keep frame-generation code in the scratch script, not in the chat — summarize what the animation does instead of pasting full code back to the user unless they ask to see it.

## Workflow notes

- All generated GIFs must go under `/tmp` or the scratch directory (see the global scratch-directory convention) unless the user explicitly wants them kept in the project repo.
- Always run `scripts/core/validators.py`'s `validate_gif`/`is_slack_ready` on the final output before presenting it as done.
- Default to CLI/script-based generation; do not attempt to call an external "Slack GIF" service or API — this skill is purely local PIL/imageio based.
