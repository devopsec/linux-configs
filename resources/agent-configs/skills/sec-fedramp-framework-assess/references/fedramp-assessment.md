# FedRAMP evidence map

Reference checked 2026-10-28: FedRAMP's 2026 Rev 5 control reference identifies NIST SP 800-53 Revision 5.2.0. Confirm the live authorization path, baseline, agency instructions, and ruleset; do not assume that every system uses Rev 5 or that the published reference supersedes agency/AO direction.

| Control families | Evidence examples | Assessment focus |
|---|---|---|
| AC, IA — access and identity | User/service identity inventory, role and group grants, MFA, account lifecycle, access review | Map identities to approval, role, activity, and termination; test least privilege and privileged access. |
| AU — audit and accountability | Audit configuration and samples, protected log stores, review/alert tickets, time correlation | Check required event coverage, fields, protection, correlation, review, and retention against the approved baseline. |
| CM, RA, SI — configuration, risk, integrity | Boundary/component inventory, configuration baselines, vulnerability/patch data, scan and remediation records | Reconcile assets and scan coverage to the authorization boundary; sample findings through remediation and retest. |
| CP, IR — contingency and incident response | Approved plans, backup/restore and failover tests, incident exercises and records | Verify recovery objectives, procedure execution, escalation, and current agency reporting duties. |
| SC, MP — communications, protection, media | Boundary/data-flow diagrams, cryptographic settings, storage controls, media handling | Validate cryptographic and data-flow requirements against the current authorization package and applicable validated modules. |
| CA, PL — assessment, authorization, planning | SSP, assessment plan/report, POA&M, monitoring plan, interconnection records | Trace implementation, inheritance, owner, evidence, milestones, and closure proof to the authorized baseline. |

## Authorization package

Maintain the approved SSP, control implementation summary, system boundary and data-flow diagrams, assessment artifacts, POA&M with owners/milestones, component inventory, interconnection agreements, and continuous-monitoring records required for the exact authorization. Keep provider inheritance distinct from customer implementation and evidence.

Official references: [FedRAMP 2026 Rev 5 control reference](https://www.fedramp.gov/2026/reference/controls) and [FedRAMP Rev 5 guidance](https://www.fedramp.gov/2026/reference/rev5-control-guidance).