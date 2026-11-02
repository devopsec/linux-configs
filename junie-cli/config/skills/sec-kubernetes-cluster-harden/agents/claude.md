# Claude specifics — Kubernetes cluster hardening

- Run authorized scans in report-only mode and distinguish scanner findings from verified impact.
- Keep findings and command output sanitized; do not store cluster secrets in reports.
- Require explicit approval before policy enforcement, remediation, or privileged scanner deployment.
