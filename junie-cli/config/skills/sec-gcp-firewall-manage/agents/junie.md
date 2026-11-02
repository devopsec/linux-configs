# Junie specifics — GCP firewall

- Resolve project, VPC, target, port, and source CIDRs only from approved runtime input/configuration.
- Prefer reviewed IaC plans, service-account targets, and firewall logging; do not apply changes without approval.
- Protect project and network identifiers in summaries; make no commits.