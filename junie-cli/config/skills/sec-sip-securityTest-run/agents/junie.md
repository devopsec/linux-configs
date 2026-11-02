# Junie specifics — SIP security testing

- Require written authorization for one named test endpoint; carrier/partner systems are excluded by default.
- Limit execution to reviewed low-rate listener checks and at most one approved functional call; no enumeration, fuzzing, or load.
- Protect/redact call traces and endpoint details; make no commits.