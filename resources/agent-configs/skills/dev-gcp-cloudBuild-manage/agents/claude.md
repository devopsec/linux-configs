# Claude specifics — dev-gcp-cloudBuild-manage

- Read the active reference branch and project companion only when applicable; do not copy local settings into generic guidance.
- Review trigger configuration, pipeline YAML, identity permissions, and secret exposure together before proposing a change.
- Keep PR/main/release identities distinct and make required validation and scan steps explicit `waitFor` prerequisites to publishing.
- Never weaken a blocking gate silently or expose secrets to untrusted PR code; call out any approved exception and expiry.
- Do not trigger builds or mutate triggers/IAM/artifacts without explicit approval; redact identifiers and do not commit.
