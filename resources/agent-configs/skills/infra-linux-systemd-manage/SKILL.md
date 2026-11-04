---
name: infra-linux-systemd-manage
description: "Administer Linux systemd services, timers, drop-ins, hardening, resource limits, and journal logs. Use when a task mentions systemctl, unit files, service startup/restarts, systemd-analyze, journalctl, timer schedules, or systemd sandboxing."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/servers/systemd-services]
  license: MIT
---

# Linux systemd service management

Use this skill to inspect, change, validate, and operate systemd service and timer units on Debian-family and RHEL-family hosts. Follow a repository's existing install conventions when the unit is shipped as code.

## Triggers

- Create, debug, harden, or override a `.service` unit.
- Add or repair a `.timer`, drop-in, or systemd resource limit.
- Diagnose `systemctl` state, restart loops, failed boot jobs, or `journalctl` output.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or host runbook if present
IF task targets a service unit shipped by a repository
  REFERENCE its installer and shipped unit (read-only; preserve established paths and ownership)
REFERENCE "references/systemd.md"
CACHE only the relevant unit, timer, or journal guidance
```

## Workflow

1. Identify distribution, systemd version, unit source, production status, and the expected user/group.
2. Capture `systemctl cat <unit>`, `systemctl show <unit> -p FragmentPath,DropInPaths,Result,NRestarts`, and relevant journal entries before editing.
3. Prefer repository-owned unit files or an admin drop-in; reset list-valued directives before replacing them.
4. Validate with `systemd-analyze verify <unit-or-file>` and, for sandbox changes, `systemd-analyze security <unit>`; test on a non-production host when practical.
5. Run `systemctl daemon-reload`, then reload only if supported; otherwise get approval before restarting a production service.
6. Verify active state, health, logs, and dependent service behavior; document the change and rollback.

## Safety

- Never put credentials in unit files or committed `Environment=` lines; reference a protected `EnvironmentFile=` or a secret manager.
- Add sandbox restrictions incrementally; `ProtectSystem=strict`, `ProtectHome`, address-family filters, and syscall filters can break legitimate paths or calls.
- Do not use `systemctl revert` without explicit approval; it removes local overrides.

## Related skills

- Service account and sudo setup → `infra-linux-users-manage`
- Sysctl/kernel tuning and file-descriptor ceilings → `infra-linux-perf-tune`
- Package-provided units and service packages → `infra-linux-packages-manage`
- SIP services and Kamailio-specific operations → `dev-kamailio-platform-manage`

## References

- [references/systemd.md](references/systemd.md) — unit files, timers, drop-ins, hardening, resource limits, and journal triage.
