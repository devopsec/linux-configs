# Claude Specifics for Infra Llm Finetuning Run

## Context & Tuning
- Load only `references/llm-fineTuning.md` and the selected immutable trainer/model configuration; validate a tiny sample before a full run.

## Instructions Overrides
- Keep datasets private, de-identified, versioned, and isolated from held-out evaluation data.

## Performance Notes
- Gate registration on task, regression, safety, and latency metrics; do not publish implicitly.
