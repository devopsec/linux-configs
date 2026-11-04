# Claude specifics — infra-podman-container-manage

## Context & Tuning
- Load the Podman reference for the active distribution, SELinux, rootless, or Quadlet question.
- Do not assume Docker daemon behavior or rootful privileges.
- Validate a Quadlet/systemd proposal before suggesting activation.
- Keep registry credentials and host secrets out of output.
