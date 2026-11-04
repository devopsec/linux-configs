# Claude Specifics for Infra Nginx Reverseproxy Manage

## Context & Tuning
- Follow the configured nginx/Traefik default and validate the active configuration before reload.
- Trust forwarded client IPs only through explicitly approved proxy hops.

## Instructions Overrides
- Ask before production restarts, public dashboard exposure, or TLS policy changes.
- Never reveal private keys, ACME state, or secret-bearing URLs.
