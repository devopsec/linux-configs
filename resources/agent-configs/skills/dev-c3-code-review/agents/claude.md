# Claude specifics — dev-c3-code-review

- If a review command or tool specifies an output format (e.g. a findings tool), use it instead
  of the markdown template.
- Run `review-scan.sh` and `scan-legacy.sh` in one turn (independent), then Read only flagged
  regions and changed functions with offsets.
- Large diffs: delegate per-directory reading to an Explore agent with the checklist section
  names; verify everything it reports yourself before including it.
- Building runs project `exec` scripts and `$exec` only with `--trust=full` — never pass that
  flag for code you're reviewing without asking. Don't edit files during the review.
