---
name: sec-ops-forensics-collect
description: "Preserve and collect host and cloud evidence during an authorized incident, including volatile state, logs, disk snapshots, hashes, and chain-of-custody records. Use when a task mentions digital forensics, evidence collection, memory capture, disk imaging, forensic snapshots, evidence upload, or chain of custody."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/operations/incident-response
  license: MIT
---

# Incident forensics collection

Collect the minimum defensible evidence using documented, repeatable steps. Collection changes system state, so coordinate with the IC and analyze copies rather than originals.

## Triggers

- Evidence collection, chain of custody, memory capture, disk snapshot, forensic image
- Host logs, process/network state, audit exports, or evidence storage

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF task needs a site evidence destination or cloud target
  IF file "~/.junie/custom/configs/security/incident-response.toml" exists
    REFERENCE "~/.junie/custom/configs/security/incident-response.toml"
  ELSE
    ask the user for the approved evidence bucket and target identifiers
IF task involves host collection, volatility order, snapshots, hashing, or custody
  REFERENCE "references/evidence-collection.md"
IF executing the bundled Linux collector
  REFERENCE "scripts/collect-evidence.sh"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Confirm authority, incident ID, collection window, target, analysis capability, and approved evidence destination.
2. Record the initial state and collect volatile data before less volatile data when safe; minimize changes and document each command.
3. Use the bundled collector only after reviewing its scope and verifying its hash on the host; run it with least privilege that still captures required evidence.
4. Hash each evidence item at collection and transfer; preserve originals and perform analysis on a verified copy or read-only snapshot.
5. Upload only to the approved restricted destination, verify access logging and encryption, and update the custody record.

## Safety

- Evidence may contain personal data and credentials; store it only in an access-controlled, encrypted location.
- Do not collect credential material, private keys, or unrelated user data unless explicitly authorized and legally required.
- Do not install unverified tools or run destructive containment from a collection script.

## Related skills

- Incident command and communications → `sec-ops-incident-respond`
- SIP-specific abuse and traffic evidence → `sec-sip-fraud-respond`
- Audit-log configuration and retrieval → `sec-gcp-auditLogs-manage`
