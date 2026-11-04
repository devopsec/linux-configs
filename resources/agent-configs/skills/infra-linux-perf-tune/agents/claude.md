# Claude Specifics for Infra Linux Perf Tune

## Context & Tuning
- Use only measured workload data and the applicable network, CPU, memory, or I/O guidance.
- Keep tuning values as runtime inputs and require a rollback plan.

## Instructions Overrides
- Do not run active benchmarks on production or raw data devices without explicit approval.
- Keep secrets and customer traffic details out of the response.
