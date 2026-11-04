# Junie specifics — sec-container-runtime-harden

## Context & Tuning
- Read the configured security TOML if present; otherwise use the documented default scanner and thresholds.
- Scan the exact image digest and distinguish exploitable findings from documented exceptions.
- Never relax a security gate or suggest `--privileged` as a shortcut.
- Keep scan artifacts, registry credentials, and host details confidential.
