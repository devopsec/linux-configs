# Junie specifics — infra-prometheus-metrics-manage

- Run `promtool`/`amtool` validation before proposing rollout.
- Treat the included scripts as read-only; never enable xtrace while handling credentials.
- Keep scrape endpoints private and labels low-cardinality; no commits.
