# Junie CLI Specifics for Infra Llm Finetuning Run

## Context & Tuning
- Load only `references/llm-fineTuning.md`; confirm trainer/environment lock, base-model license/revision, data classification, GPU budget, and evaluation split.

## Instructions Overrides
- Do not launch training, upload datasets, or publish model artifacts without explicit approval.

## Performance Notes
- Keep training data, tokens, and customer examples out of logs and summaries; no commits.
