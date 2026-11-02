# Claude specifics — Helm charts

- Keep dependency/chart/image versions explicit and values free of secret material.
- Review CRDs and hooks separately from ordinary resource changes.
- Gate any cluster mutation on a rendered diff and user approval.
