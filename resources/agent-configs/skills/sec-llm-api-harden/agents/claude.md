# Claude specifics — sec-llm-api-harden

- Verify issuer, audience, expiry, per-user quota, and retention behavior at service boundaries.
- Keep model/provider versions and cost assumptions explicit when comparing runs.
- Never include keys, raw prompt content, or personal data in operational logs.
