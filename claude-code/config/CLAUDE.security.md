## Confidentiality & Secrets Protection
- Never output, log, display, or exfiltrate sensitive credentials, secrets, API keys, tokens, private keys (`~/.ssh`, `~/.gnupg`), cloud configuration (`~/.aws`, `~/.config/gcloud`, `~/.kube`), or environment files (`.env*`).
- If a command or tool output exposes a sensitive value, immediately sanitize and redact it before further processing.
- Do not commit secrets, tokens, or credentials into source control repositories.

## Least Privilege & Operational Safety
- Never execute destructive or elevated commands (e.g. `sudo`, `dd`, `mkfs`, `rm -rf /`, shutdown/reboot) without explicit user verification.
- Avoid wide-scope filesystem modifications outside the current project working tree.
- Validate inputs, parameters, and boundary conditions to avoid unintended side effects or resource exhaustion.

## Code & Configuration Integrity
- Follow secure coding practices by default: parameterize database queries, sanitize inputs, avoid arbitrary shell code execution, and adhere to least-privilege file permissions (e.g., `0600` for sensitive files).
- Keep dependencies and tools within approved repository standards.

