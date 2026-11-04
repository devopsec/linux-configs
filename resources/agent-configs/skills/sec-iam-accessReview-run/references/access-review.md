# Identity access review reference

## Review population

Identify all authoritative identity surfaces in scope: central identity provider, cloud and infrastructure grants, databases, source control, CI/CD, SaaS, hosts, emergency access, groups, service identities, and external users. Include inherited group/resource permissions and delegated administration. Reconcile sources before sampling and document unsupported or missing surfaces.

## Review procedure

1. Define review period, boundary, reviewer independence, system owners, evidence retention, completion date, and escalation path.
2. Export dated grants and metadata using approved read-only access; record query/filter parameters and source timestamps.
3. Correlate each identity with owner, purpose, privilege, environment/data scope, approval, status, and reliable activity evidence.
4. Prioritize privileged access, production/data access, external identities, non-human accounts, key-backed identities, dormant/orphaned grants, and separation-of-duties conflicts.
5. Obtain an owner/reviewer decision for each item: retain, modify, revoke, or time-limited exception with rationale and expiry.
6. Track approved actions to completion in the authoritative system; independently verify high-risk changes and preserve before/after evidence.
7. Report total population, reviewed count, exclusions, overdue/non-response items, decisions, exceptions, completion status, and evidence period.

## Safeguards

- Review effective access, not just directly assigned roles; check group nesting, inheritance, resource-level policies, impersonation, and deployment permissions.
- Do not treat absent or unreliable last-used metadata as proof of inactivity.
- Never collect key material, credentials, authentication factors, or unnecessary personal data. Restrict and expire evidence under policy.
- Do not automatically disable accounts based on an inventory flag. Confirm impact and obtain the authorized decision.

Quarterly privileged/service identity and semiannual standard-user reviews may be planning examples only; set cadence from approved policy, contracts, risk, and framework requirements.