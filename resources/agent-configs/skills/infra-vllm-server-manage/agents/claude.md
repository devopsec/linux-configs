# Claude Specifics for Infra Vllm Server Manage

## Context & Tuning
- Load only `references/vllm.md` and use the configured immutable model revision; treat hardware and concurrency values as inputs.

## Instructions Overrides
- Keep credentials private and the server behind an authenticated gateway; estimate memory and spend before scaling.

## Performance Notes
- Benchmark TTFT, inter-token latency, throughput, and errors before recommending tuning changes.
