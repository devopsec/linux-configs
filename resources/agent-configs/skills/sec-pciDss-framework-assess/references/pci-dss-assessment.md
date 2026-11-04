# PCI DSS evidence map

Baseline checked 2026-10-28: PCI DSS v4.0.1 was identified by PCI SSC as its current published version in 2026. Confirm the release, assessment instrument, and supporting materials with PCI SSC and the QSA/acquirer before relying on this map.

| Topic | Evidence examples | Assessment focus |
|---|---|---|
| Scope and Req. 1 — network security | Card-data flow/CDE diagrams, network policy and routing exports, boundary and segmentation tests | Identify systems that store, process, transmit, or can affect account-data security; do not assume a network label removes scope. |
| Req. 2, 5, 6 — configuration, malware, software | Secure baselines, patch/vulnerability records, source review, build/release checks, artifact provenance | Sample controls and remediation within the confirmed scope. |
| Req. 3–4 — stored/transmitted account data and cryptography | Data-flow/schema review, encryption/key controls, TLS endpoints, masking or substitution design | Verify data minimization and key handling. Do not collect sensitive authentication data after authorization. |
| Req. 7–8 — access and authentication | Identity/grant exports, MFA, service identity/key metadata, privileged access, repository and deployment permissions | Test unique identities, need-to-know, required authentication, joiner/mover/leaver samples, and access paths into or affecting the CDE. |
| Req. 10 — logging | Audit event configuration and samples, log access/retention, time synchronization, review and alert evidence | Verify coverage, event identity/time/outcome/source, protection, and review under the applicable requirements. |
| Req. 11–12 — testing, policy, third parties, incident response | Approved scans and tests, findings/retests, policies, provider agreements, responsibility matrix, incident exercises | Confirm required frequency, scope, and service-provider responsibility with the QSA. |

## Scope and evidence cautions

- Card-data substitution, outsourcing, or segmentation may change scope only when the implementation satisfies applicable requirements; obtain the QSA's determination.
- Do not collect PAN, CVV, track data, PIN/PIN block, credentials, or key material for an assessment. Use redacted configuration and controlled test records.
- Check whether payment data can enter logs, analytics, support records, build artifacts, or other systems outside the intended flow.

Official references: [PCI SSC PCI DSS v4.0.1 publication](https://blog.pcisecuritystandards.org/just-published-pci-dss-v4-0-1) and [PCI SSC 2026 update identifying the current published version](https://blog.pcisecuritystandards.org/request-for-comments-pci-data-security-standard-pci-dss-v4.0.1).