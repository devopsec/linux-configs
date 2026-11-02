# Junie specifics — network VPN

- Read VPN TOML when available; ask for peer, endpoint, and route inputs rather than inventing them.
- Prefer IAP for GCP administration when adequate; safeguard per-peer keys and establish rollback before route changes.
- Redact all secret material and make no commits.