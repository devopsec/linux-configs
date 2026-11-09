# Junie CLI Specifics for Infra Nginx Benchmark Run

## Context & Tuning
- Confirm the target and rate cap with the user before the first load run; state URL, tool, rate, duration, and connection count in the plan.
- Prefer a local container rig (`references/rig-configs.md`); use fully qualified image names with podman and `:Z` bind mounts.
- Run long benchmarks with a timeout sized to the run plus margin; collect raw outputs in `/tmp/bench`.

## Instructions Overrides
- No commits; no production load tests without explicit approval.
- Do not change sysctl/ulimit on the host without approval; record and revert any change.
- Report numbers with spread and error rate, never RPS alone.
