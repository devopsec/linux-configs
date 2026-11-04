# Alerting & on-call

## Severity model

| Severity | Meaning | Delivery | Example |
|---|---|---|---|
| `page` | user-visible impact now or imminent; needs human in minutes | pager (24/7) | SLO fast burn, service unavailable, database primary down |
| `ticket` | degradation / budget slow burn / capacity trend; next business day | chat + ticket | SLO slow burn, disk full in 3 days, cert expires in 14d |
| `info` | context only | dashboard / chat, no notification | deploys, autoscaling |

Rules: alert on **symptoms** (users) for pages, **causes** for tickets. Every alert: owner, `runbook_url`, actionable. No alert that nobody acts on survives the weekly review.

## Alert hygiene

- `for:` ≥ 2–5 min for pages (avoid flapping), longer for tickets.
- Group by `alertname, service`; inhibit tickets when a page for the same service is firing; inhibit everything downstream of a host-down.
- Silence for maintenance with expiry + comment: `amtool silence add service=<service> --duration=2h --comment="<change id>"`.
- Track: pages per week per person, % actionable, MTTA/MTTR.
- Dead-man's switch: an always-firing `Watchdog` alert routed to an external heartbeat (e.g. healthchecks/PagerDuty heartbeat) so a dead Prometheus/Alertmanager is itself detected.

## Routing targets

- Alertmanager → PagerDuty / Opsgenie / Grafana OnCall (IRM) / chat webhooks — config in `prometheus-grafana.md` §6; secrets via `*_file`.
- Cloud Monitoring alert policies → notification channels (email, PagerDuty, Pub/Sub, webhooks), managed with OpenTofu (`google_monitoring_notification_channel`). Pub/Sub channel → automation (e.g. Cloud Run function) if auto-remediation is wanted.
- PagerDuty / Opsgenie schedules and escalation policies as code: Terraform/OpenTofu providers `PagerDuty/pagerduty`, `opsgenie/opsgenie` — keep API tokens in Secret Manager, passed via provider env vars (`PAGERDUTY_TOKEN`).

## On-call practice

- Primary + secondary, weekly rotation, handoff with open-issues note; escalation: primary 5–10 min → secondary → engineering lead.
- Paging SLA: ack ≤ 5 min (page), ticket triage next business day.
- Recovery time after heavy nights; max ~1 week in 4 on primary.
- Test the path monthly: synthetic page end-to-end.

## Runbook template

```markdown
# <AlertName>
**Severity / owner:** page / <team>    **Dashboard:** <link>    **Last reviewed:** <date>

## What it means
<symptom, user impact, SLO affected>

## Triage (read-only first)
1. Dashboard <link>: is it one host or all? started after a deploy (annotations)?
2. `systemctl status <unit>`; `journalctl -u <unit> --since "-30 min"`
3. Check the affected service's read-only health endpoint, recent deploy, and service-specific logs.
4. Database: connections/locks diagnostics → the matching engine skill under `infra-*-server-administer`.
5. Cloud Logging query: `resource.type="gce_instance" severity>=ERROR labels.service="<svc>"`

## Mitigate
- Roll back last release (Cloud Build release trigger / previous artifact) — preferred over hot fixes
- Drain/fail over: <steps>
- **Destructive steps (restart primary DB, flush caches, block IP ranges) require IC approval**

## Escalate
<who, when>

## Afterwards
Incident doc → `sec-ops-incident-respond`; fix alert if it was noisy/late.
```

Dropped from upstream: kubectl-centric runbook steps and the "delete the postgres pod" remediation (unsafe default); hardcoded `SECRET_KEY` in the Grafana OnCall compose example.
