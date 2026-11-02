# Google Kubernetes Engine

Project, region, network, subnets, control-plane authorized ranges, IP ranges, node shapes, and cluster version are runtime inputs. Check supported versions for the selected release channel in `gcloud container get-server-config`; pin exact cluster and node versions in production IaC rather than relying on a moving default.

## Choose a cluster mode

| Mode | Use when | Considerations |
|---|---|---|
| Autopilot | General stateless services, jobs, and managed scaling | Google manages nodes; restricted privileged/host-level features. |
| Standard | Explicit node-pool, GPU, kernel, DaemonSet, or host-network needs | Operator owns node sizing, upgrades, and more security controls. |

If a workload requires host networking or privileged access, first verify that it cannot run on a dedicated VM or a constrained Standard pool. Do not select Standard just to bypass workload security constraints.

## Private cluster and node identity

Use private nodes, a private control plane where supported, master authorized networks with approved admin ranges, VPC-native IP aliasing, release channels, Shielded nodes, auto-repair, and planned auto-upgrade. Ensure private nodes have only required egress (Cloud NAT for external registries; Private Google Access for supported Google APIs).

Autopilot example; replace all network and control-plane ranges with reviewed inputs:

```bash
gcloud container clusters create-auto "$CLUSTER" \
  --project="$PROJECT_ID" --region="$REGION" --release-channel=regular \
  --network="$VPC" --subnetwork="$SUBNET" \
  --enable-private-nodes --master-ipv4-cidr="$CONTROL_PLANE_CIDR" \
  --enable-master-authorized-networks --master-authorized-networks="$ADMIN_CIDRS"
```

Standard mode should use a dedicated node service account with only node logging/monitoring and image-pull permissions. Do not use the default Compute Engine service account with broad project roles.

## Workload Identity

Prefer direct IAM principal bindings for Kubernetes service accounts when supported; do not create or mount a service-account key. Grant the KSA access only to the resource it needs.

```bash
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
gcloud secrets add-iam-policy-binding "$SECRET_ID" --project="$SECRET_PROJECT" \
  --role=roles/secretmanager.secretAccessor \
  --member="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${NAMESPACE}/sa/${KSA}"
```

Use GSA impersonation only when a Google API requires it; bind `roles/iam.workloadIdentityUser` to the exact KSA and annotate the KSA. Keep Secret Manager CSI/External Secrets configuration in its owning workload/security reference.

## Ingress and operations

- Prefer Gateway API for new HTTP(S) routing where supported; plan CRD/controller lifecycle and health-check policy.
- Use external passthrough load balancers only for supported L4 needs. Validate protocol/address behavior before selecting a cluster-level design; dedicated VMs may be the better fit for specialized public endpoints.
- Enable required control-plane/workload logs and monitoring with retention appropriate to policy.
- Back up manifests and persistent data with Backup for GKE or the platform recovery workflow; test restores.

```bash
gcloud container clusters get-credentials "$CLUSTER" --project="$PROJECT_ID" --region="$REGION"
gcloud container clusters describe "$CLUSTER" --project="$PROJECT_ID" --region="$REGION"
gcloud container get-server-config --project="$PROJECT_ID" --region="$REGION"
gcloud container operations list --project="$PROJECT_ID" --region="$REGION" --filter='status!=DONE'
```

Cluster upgrades, node pool replacement, and authorized-network edits can interrupt workloads or lock operators out. Confirm maintenance window, control-plane/node version compatibility, backup, rollback path, and exact environment before action.

## References

- [GKE cluster configuration](https://cloud.google.com/kubernetes-engine/docs/how-to/creating-a-regional-cluster) — checked 2026-10-28.
- [GKE Workload Identity Federation](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) — checked 2026-10-28.