# Evidence collection and chain of custody

## Contents

- Order of volatility
- Host collector
- Memory and disk evidence
- Cloud evidence
- Custody record

## Order of volatility

Capture the most volatile evidence first when the team can preserve and analyze it:

1. Memory, if qualified responders and tooling are available
2. Active connections, processes, and logged-in users
3. Temporary files and transient service state
4. Logs and audit records
5. Disk snapshots/images
6. Cloud configuration and control-plane records

Every collection action changes state. Record the action, operator, tool, time source, and resulting hash; prefer a separate evidence disk or approved remote destination over the suspect filesystem.

## Host collector

The bundled `scripts/collect-evidence.sh` gathers bounded host metadata and logs. Review its exact scope, verify its integrity after transfer, and choose an output directory on a separate mounted evidence volume:

```bash
sha256sum collect-evidence.sh
./collect-evidence.sh -o <mounted-evidence-directory> \
  -s "<approved-time-window>" -u <additional-unit> <incident-id>
```

The collector is read-only with respect to the host services, but it creates an archive and reads sensitive process/user/log metadata. Run with root only when required for the approved scope; a non-root collection may be incomplete. Protect the archive as sensitive evidence.

Do not collect account-hash databases, private keys, credential payloads, or entire unrelated log trees. The script does not block, kill, or quarantine a host.

## Memory and disk evidence

Capture memory only when responders can safely acquire, preserve, and analyze it. Use a trusted tool source and verify its published checksum/signature before transfer; record any kernel or agent change. Hash the captured image immediately.

For disk analysis, work from a snapshot or verified copy attached read-only to a separate forensic system. Mount read-only with execution disabled where supported. Record filesystem and mount options, and never analyze the original suspect disk in place.

## Cloud evidence

Use the cloud provider's supported snapshot and audit-export controls with identifiers read from approved incident configuration. Record source resource, project/account, region, snapshot identifier, operator, timestamp, and policy changes. Coordinate with the IC before isolation or detachment because automation may recreate a resource or interrupt service.

If uploading to Cloud Storage, read the evidence destination from `~/.junie/custom/configs/security/incident-response.toml` or ask the user. Confirm encryption, restricted IAM, access logging, and retention before transfer. A retention lock is irreversible: obtain explicit approval and test on a disposable destination first.

## Custody record

Record one row for every item and transfer:

| Item | SHA-256 | Collector | UTC time | Source | Restricted location | Access record |
|---|---|---|---|---|---|---|
| | | | | | | |

Hash at collection and each transfer, verify with `sha256sum -c`, preserve the original, and perform analysis on copies. Restrict the custody record itself if it contains personal or sensitive identifiers.