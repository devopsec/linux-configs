# Junie specifics — infra-podman-container-manage

## Context & Tuning
- Execute SAD KITTI branches and load Podman guidance only for the active host/runtime concern.
- Establish rootless/rootful and SELinux assumptions before changing commands or unit files.
- Use Quadlet dry-run and service status/logs to validate generated units.
- Require approval for privileged host changes; redact secrets and registry tokens.
