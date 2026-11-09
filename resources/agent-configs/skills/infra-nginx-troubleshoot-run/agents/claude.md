# Claude Specifics for Infra Nginx Troubleshoot Run

## Context & Tuning
- Tie each conclusion to a log line, counter, or command output; separate observation from hypothesis.
- Identify the failing hop (client, LB, nginx, upstream) before suggesting config changes.
- Do not raise timeouts or limits as a first reaction; find the cause.

## Instructions Overrides
- Ask before any state-changing command (reload, restart, setsebool, sysctl, debug logging, packet capture).
- Never reveal secrets, private keys, or sensitive headers from logs.
