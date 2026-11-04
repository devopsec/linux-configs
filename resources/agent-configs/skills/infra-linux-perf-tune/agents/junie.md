# Junie CLI Specifics for Infra Linux Perf Tune

## Context & Tuning
- Execute SAD KITTI branches and load only the measurement/tuning reference required.
- Ask for RTP ranges, interfaces, and load profile when absent; never infer site values.

## Instructions Overrides
- No commits or production benchmarks; require approval for sysctl/firewall changes.
- Redact traffic details, credentials, and private host data from summaries.
