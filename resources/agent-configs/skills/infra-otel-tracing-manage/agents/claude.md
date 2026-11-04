# Claude specifics — infra-otel-tracing-manage

- Keep manual and automatic instrumentation from creating duplicate spans.
- Review redaction, sampling, and TLS on cross-host OTLP before deployment.
- Do not restart production agents without an explicit request.
