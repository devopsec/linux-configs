# Claude specifics — infra-gcp-artifactRegistry-manage

## Context & Tuning
- Load only Artifact Registry-specific instructions and request the project/region/repository when absent.
- Never recommend long-lived service-account keys when workload identity or attached identity is available.
- Distinguish mutable tags from immutable digests in release summaries.
- Require approval before changing IAM, cleanup policy, or published artifacts.
