# Junie specifics — GCP Compute Engine

- Execute only the matching SAD KITTI reference branch; inspect before proposing mutation.
- Keep managed resources in IaC and request approval before destructive or production operations.
- Treat project, zone, CIDR, machine size, and hostnames as runtime inputs; redact them in summaries.
