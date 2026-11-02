# Linux host audit trails

## Contents

- Event scope
- Journald and authentication logs
- Auditd queries
- Rsyslog TLS forwarding
- Structured application events
- Integrity and review

## Event scope

Choose events based on the investigation and compliance need: authentication, privilege changes, administrative configuration changes, application actions, and service lifecycle. Prefer stable event fields such as UTC timestamp, actor, action, resource, and result. Keep the host audit policy and event vocabulary documented alongside the service owner.

Audit rule content belongs to the host-hardening owner. This skill covers collection, retention, forwarding, query, and integrity.

## Journald and authentication logs

Persist journals where local retention supports triage, and bound disk usage according to available storage and policy:

```ini
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=<approved-size>
SystemKeepFree=<approved-free-space>
MaxRetentionSec=<approved-retention>
```

```bash
journalctl --since "<time-window>" -o json-pretty
journalctl --since "<time-window>" _SYSTEMD_UNIT=<unit>.service
journalctl --since "<time-window>" _COMM=sshd
```

Journal sealing requires a separately protected verification key and supported setup; it does not replace remote shipping. Use RHEL-family and Debian authentication log locations only as platform-specific fallbacks when journald is unavailable.

## Auditd queries

Use the key names defined by the approved audit rule set:

```bash
ausearch -k <rule-key> -ts recent -i
ausearch -m USER_LOGIN,USER_AUTH -sv no -ts recent -i
aureport --auth --failed --summary
```

Do not improvise broad audit rules on a production system. Validate rule syntax and expected event volume with the host-hardening owner before rollout.

## Rsyslog TLS forwarding

Forward over mutually authenticated TLS where supported. Restrict the receiver identity and buffer boundedly during outages:

```text
global(
  DefaultNetstreamDriver="gtls"
  DefaultNetstreamDriverCAFile="<trusted-ca-file>"
)
module(load="imfile")
input(type="imfile" File="<auth-log-path>" Tag="auth" Facility="authpriv")

action(type="omfwd" target="<siem-host>" port="<tls-port>" protocol="tcp"
  StreamDriver="gtls" StreamDriverMode="1" StreamDriverAuthMode="x509/name"
  StreamDriverPermittedPeers="<siem-host>"
  queue.type="LinkedList" queue.maxDiskSpace="<approved-size>"
  queue.saveOnShutdown="on" action.resumeRetryCount="-1")
```

Validate with the local rsyslog configuration test before reload. Monitor queue growth, remote certificate expiry, and forwarding failures.

## Structured application events

Emit one JSON object per event and avoid credentials or raw personal data. Keep field names stable and distinguish success, denial, and failure:

```json
{
  "timestamp": "<UTC timestamp>",
  "actor": "<pseudonymous actor>",
  "action": "<action>",
  "resource": "<resource identifier>",
  "result": "success|denied|failure"
}
```

Validate parser mappings and redaction rules before forwarding; never serialize whole request objects into audit logs.

## Integrity and review

- Ship logs off-host quickly; a compromised host can alter logs that have not left its trust boundary.
- Restrict destinations to security/audit roles and enable access logging on the destination.
- Alert on missing ingestion, shipper stoppage, unexpected retention changes, and loss of remote connectivity.
- Test restore and retention behavior periodically, and preserve original evidence before investigating a compromised host.