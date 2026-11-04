# Junie specifics — Kubernetes workloads

- Confirm context and namespace before invoking cluster commands; begin with read-only diagnostics.
- Treat logs and resource descriptions as potentially sensitive; redact before sharing.
- Require explicit approval for rollouts, deletion, exec/debug pods, and node maintenance.
