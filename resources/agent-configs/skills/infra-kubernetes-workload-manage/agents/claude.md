# Claude specifics — Kubernetes workloads

- Check cluster, namespace, and management tool before recommending a manifest change.
- Prefer logs and events with a bounded time/line window; do not repeat secret-bearing output.
- Gate all mutating commands on user approval.
