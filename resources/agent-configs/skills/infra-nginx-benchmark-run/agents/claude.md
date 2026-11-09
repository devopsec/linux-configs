# Claude Specifics for Infra Nginx Benchmark Run

## Context & Tuning
- Do not claim a tuning change helps without a baseline, repeated runs, percentiles, and error rate.
- Name the bottleneck with evidence (CPU, file descriptors, ports, upstream, generator) before recommending a change.
- State tool limitations (closed-loop vs fixed-rate, coordinated omission) when presenting latency numbers.

## Instructions Overrides
- Ask before any production or shared-host load, and before system-level tuning.
- Never aim load at third-party systems.
