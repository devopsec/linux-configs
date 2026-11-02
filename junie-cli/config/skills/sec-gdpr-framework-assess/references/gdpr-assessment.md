# GDPR evidence map

Baseline checked 2026-10-28: Regulation (EU) 2016/679. Use the applicable current law and jurisdiction-specific guidance; ask the privacy lead or counsel to confirm legal interpretation.

| Theme | Evidence to map | Assessment focus |
|---|---|---|
| Articles 5, 6, 9, 30 — principles, lawful basis, special categories, records | Approved processing records, data-flow maps, purposes, data categories, recipients, retention, and owner decisions | Trace each purpose and data category to a documented basis, recipient, location, minimization measure, and review owner. Do not infer consent or another lawful basis. |
| Articles 25, 32 — design and security | Access policies, encryption/key controls, logging, monitoring, configuration, risk decisions, and tested safeguards | Compare implemented safeguards to the stated risk and verify effective access, separation of duties, and review evidence. |
| Articles 12–22 — data-subject rights | Approved DSAR workflow, identity checks, search/delete/correction test records, downstream processor coordination, and exceptions | Sample the end-to-end process; record legally retained data and rationale. Do not promise immediate removal from immutable backups without an approved policy. |
| Article 28 and Chapter V — processors and transfers | Processing agreements, subprocessor list, locations, transfer assessment, safeguards, and service-specific terms | Verify the precise processing activity, recipient, service, location, and applicable transfer mechanism. |
| Articles 32–34 — security incidents and breaches | Incident playbook, incident records, notification decision, escalation and tabletop evidence | Verify the decision path and documentation. The Article 33 72-hour supervisory-authority notification rule is conditional; the privacy lead/counsel determines applicability and what to report. |

## Evidence handling

- Data that can identify or single out a person in context may be personal data even without a name; pseudonymization does not by itself make data anonymous.
- Prefer schemas, configuration exports, counts, redacted examples, and controlled test records over raw personal data.
- Include copies, analytics, logs, processors, exports, backups, retention jobs, and rights-handling paths in the processing map.
- Restrict evidence access and retention; assessment exports and query results may themselves contain personal data.

Official source: [Regulation (EU) 2016/679 on EUR-Lex](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng).