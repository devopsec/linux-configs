# Incident indicator triage

## Record indicators

Track each indicator with source, first/last observed UTC time, confidence, affected asset, and action taken:

- Network address or range, domain, URL, or certificate fingerprint
- File hash, path, process name, or persistence mechanism
- User, service identity, key identifier, or authentication event
- Resource, API action, data set, or affected business record category

Treat identifiers and captured events as sensitive; do not paste customer data into public search services.

## Triage method

1. Preserve the original event/log reference and record its clock/source before searching.
2. Validate the indicator against trusted sources and determine whether it is unique, shared infrastructure, or a false positive.
3. Search only authorized, bounded data sources for related events and build a timeline around the first/last observed time.
4. Correlate identity, process, network, and resource activity; distinguish confirmed activity from hypothesis.
5. Share indicators only through approved channels and include handling restrictions and confidence.

Do not block a shared address or delete a suspected file solely because it matches one indicator. Get IC approval, preserve evidence first, and choose the narrowest reversible response.

For host collection and Cloud Audit Logs, use `sec-ops-forensics-collect` and `sec-gcp-auditLogs-manage`. For SIP indicators and call records, use `sec-sip-fraud-respond`.