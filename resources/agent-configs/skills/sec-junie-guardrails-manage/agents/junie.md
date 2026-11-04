# Junie specifics — sec-junie-guardrails-manage

- Execute SAD KITTI branches; load only the Junie or shared CI reference needed.
- Inspect global configuration by shape and rule counts only; never read credential values.
- Present global settings changes as a diff and wait for fresh approval before editing.
- No commits; redact secrets and machine-specific paths in summaries.
