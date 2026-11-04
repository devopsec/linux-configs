# systemd services, timers, and logs

## Contents

- Inspect and locate units
- Service units and drop-ins
- Timers
- Validation, rollout, and journal triage

## Inspect and locate units

Start with the effective unit and source paths; package units belong to `/usr/lib/systemd/system` or the distribution's vendor path, while local administration belongs under `/etc/systemd/system`.

```bash
systemctl cat <unit>
systemctl show <unit> -p FragmentPath,DropInPaths,Result,ExecMainStatus,NRestarts
systemctl status <unit> --no-pager
systemd-analyze --version
```

When a repository owns the unit, inspect its installer and source file read-only first, then update the repository-owned copy rather than patching a generated host file.

## Service unit pattern

Use explicit service identity and state paths. Add hardening gradually and only after confirming the application can run with each restriction.

```ini
[Unit]
Description=<purpose>
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=<service-user>
Group=<service-group>
ExecStart=/usr/local/bin/<service> --config /etc/<service>/<service>.conf
Restart=on-failure
RestartSec=<approved-delay>
UMask=0027
StateDirectory=<service>
RuntimeDirectory=<service>
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/<service>

[Install]
WantedBy=multi-user.target
```

Use `Type=notify` only when the process implements `sd_notify`; use `Type=oneshot` for bounded jobs. Never embed credentials in committed `Environment=` settings. Keep secret-bearing environment files root-owned and readable only by the service's required principals.

## Drop-ins and safe replacement

Prefer `/etc/systemd/system/<unit>.service.d/<name>.conf` over copying a vendor unit. List-valued properties append across drop-ins; clear them before replacing:

```ini
[Service]
ExecStart=
ExecStart=/usr/sbin/<service> --config <approved-path>
EnvironmentFile=
EnvironmentFile=-/etc/<service>/<service>.env
```

Inspect the merged result with `systemctl cat <unit>`. `systemctl revert <unit>` removes all administrator overrides and is destructive to local changes; do not use it without approval.

## Timers

Pair a `.timer` with a `Type=oneshot` service. Enable the timer rather than the job service; use `Persistent=true` for missed calendar runs and a randomized delay for fleet-wide jobs when appropriate.

```ini
[Unit]
Description=<job> schedule

[Timer]
OnCalendar=<approved-calendar-expression>
Persistent=true
RandomizedDelaySec=<approved-spread>
Unit=<job>.service

[Install]
WantedBy=timers.target
```

Validate calendar syntax with `systemd-analyze calendar '<expression>'`, inspect `systemctl list-timers --all`, and start the service once manually before enabling the timer.

## Validation and rollout

1. Run `systemd-analyze verify <unit-file>` and `systemd-analyze security <unit>` where relevant.
2. Review permissions, service identity, write paths, capabilities, resource limits, and dependencies.
3. Run `systemctl daemon-reload`; use `reload` only when the service supports it and its config has passed its own validator.
4. Restart only after a successful validation and an approved maintenance window; drain call-bearing services first.
5. Check `systemctl is-active <unit>` and exercise the service's health check.

Hardening candidates such as `ProtectSystem=strict`, `ProtectHome`, `PrivateDevices`, `RestrictAddressFamilies`, and `SystemCallFilter` can block legitimate filesystem, device, networking, or syscall use. Add one at a time and inspect journal/kernel denial messages.

## Journal triage

```bash
journalctl -u <unit> -b -n <count> --no-pager
journalctl -u <unit> --since '<time-window>' -p warning
journalctl -k -b -p warning
systemctl list-units --failed
systemctl show <unit> -p Result,ExecMainStatus,NRestarts
```

For previous-boot logs, confirm persistent journaling is enabled. Redact credentials, tokens, and personal data before sharing log output.