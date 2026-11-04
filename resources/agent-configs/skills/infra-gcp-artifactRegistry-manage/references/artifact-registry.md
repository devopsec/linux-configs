# Google Cloud Artifact Registry

Use Google Cloud Artifact Registry for Docker-format image repositories. Validate legacy `gcr.io` paths against the owning project's migration state before changing them.

## Artifact Registry

```bash
gcloud artifacts repositories create "${REPO}" \
  --repository-format=docker --location="${REGION}" \
  --description="service images" \
  --immutable-tags                         # tags cannot be moved once pushed
gcloud artifacts repositories describe "${REPO}" --location="${REGION}"
```

Auth (pick one):

```bash
gcloud auth configure-docker "${REGION}-docker.pkg.dev"     # writes credHelpers to docker config
gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin "https://${REGION}-docker.pkg.dev"   # short-lived (1h)
```

- CI publisher identity: grant `roles/artifactregistry.writer` **only** to the publishing identity and `reader` to deployers/VMs; Cloud Build authentication details belong to in-house `dev-gcp-cloudBuild-manage`.
- Compute Engine VMs: attached SA + `reader`; `docker-credential-gcr` or `gcloud auth configure-docker` on the host. No JSON keys on disk.
- GKE: node SA or Workload Identity with `reader`.

Push / pull / inspect:

```bash
IMG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/myapp"
docker tag myapp:dev "${IMG}:${TAG}"
docker push "${IMG}:${TAG}"
gcloud artifacts docker images list "${IMG}" --include-tags
gcloud artifacts docker images describe "${IMG}:${TAG}" --format='value(image_summary.digest)'
docker pull "${IMG}@sha256:<digest>"                        # deploy by digest
```

Cleanup policies (dry-run first):

Define deletion age, retained versions, and protected tag classes from the service's approved retention policy; do not invent retention periods or counts.

```bash
gcloud artifacts repositories set-cleanup-policies "${REPO}" --location="${REGION}" \
  --policy=policy.json --dry-run                  # inspect audit logs, then rerun without --dry-run
```

Other AR features: remote repositories (Docker Hub pull-through cache — avoids rate limits), virtual repositories, vulnerability scanning (`gcloud artifacts docker images list --show-occurrences`), VPC-SC.
Manage repos/IAM declaratively with OpenTofu (`google_artifact_registry_repository`, `google_artifact_registry_repository_iam_member`).

Signing and attestations → `sec-artifact-sbom-sign`; other registry providers use their provider-specific skills.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `denied: Permission "artifactregistry.repositories.uploadArtifacts"` | wrong SA or missing `writer`; check `gcloud auth list` |
| `unauthorized` after ~1h | access token expired; use credential helper |
| `manifest unknown` | tag/region/project typo; `images list --include-tags` |
| `tag already exists` on push | repo has immutable tags — publish a new version, never delete to force |
