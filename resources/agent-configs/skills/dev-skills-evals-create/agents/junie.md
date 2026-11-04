# Junie specifics — dev-skills-evals-create

- Execute SAD KITTI branches; run the evaluator's `--dry-run` before any live request.
- Use a copied catalog and disposable single-user runner; live calls require explicit approval.
- Never log the auth argument or include real user prompts, secrets, or PII in fixtures.
- No commits; keep result summaries limited to skill names and scores.
