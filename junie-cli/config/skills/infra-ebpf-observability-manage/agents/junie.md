# Junie specifics — infra-ebpf-observability-manage

- Confirm host/kernel scope and approval before privileged production probes.
- Use tracepoints and strict timeouts; avoid collecting payloads or unrelated process data.
- Redact findings and protect generated files; no commits.
