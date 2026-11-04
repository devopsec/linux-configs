# Claude specifics — Pub/Sub

- Confirm the delivery contract, ordering, retention, and poison-message path first.
- Use least-privilege roles and authenticated push; keep production events out of validation jobs.
- Explain backlog replay or message loss before any destructive action.
