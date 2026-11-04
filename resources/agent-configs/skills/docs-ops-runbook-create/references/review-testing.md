# Runbook review, testing, versioning, and CI

## Review checklist

- [ ] Title identifies one service and one operation; overview states when to use and when not to.
- [ ] Prerequisites list required access, tools, dependencies, and backups.
- [ ] Every step has a concrete action and an observable expected result.
- [ ] Destructive actions are labelled, previewed first, and state the point of no return.
- [ ] Verification includes specific health, log, or metric checks.
- [ ] Rollback is real, tested, and linked to backup/restore guidance; irreversible actions say so.
- [ ] Troubleshooting covers common failure modes; escalation uses roles/rotations, not personal contact data.
- [ ] Placeholders are explained, commands paste cleanly, and credentials/site values are not hardcoded.
- [ ] Owner, version, review/test dates, change log, index row, and links are current.

## Testing cadence

| Test | When | Method |
|---|---|---|
| Dry run | New procedure or major change | Execute on an approved non-production target and record expected-output differences |
| Peer walkthrough | Every material update | Another operator follows it without author assistance |
| Scheduled review | At the team's documented cadence | Select procedures and update last-tested status |
| Incident review | After real use | Record inaccurate/missing steps as tracked actions |
| Game day | Planned resilience exercise | Inject a safe failure in a test environment and follow the procedure |

Mark stale procedures clearly when they exceed the organization's test interval. Never claim a runbook was tested when only its Markdown was reviewed.

## CI lint example

Image versions checked 2026-10-28: ShellCheck `0.11.0`; `markdownlint-cli2` `0.24.0`. Pin the tags and update them through a reviewed change:

```yaml
- id: lint-runbook-scripts
  name: koalaman/shellcheck-alpine:v0.11.0
  entrypoint: sh
  args: ['-c', 'find documentation/user/runbooks -name "*.sh" -print0 | xargs -0 -r shellcheck']
- id: lint-runbook-markdown
  name: davidanson/markdownlint-cli2:v0.24.0
  args: ['documentation/user/runbooks/**/*.md']
```

Markdown lint configuration should match the repository's policy. If extracting fenced Bash blocks, pass `--shell=bash` and document any placeholder-related exclusions rather than hiding substantive diagnostics.