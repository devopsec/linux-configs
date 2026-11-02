# Kubernetes and GKE cluster hardening

This reference is for authorized, owned clusters only. Default to read-only inventory and report-only scanners. The selected Kubernetes version, admission APIs, CNI, project, namespaces, and maintenance window are runtime inputs.

## Scan configuration and versions

The example config at `assets/config.example.toml` selects `kube-bench v0.16.0` with the GKE profile in report-only mode. Kubescape `v4.0.16` and Trivy `v0.76.1` are checked alternatives for posture and image scanning. All versions were checked against official releases on 2026-10-28. Pin container images by digest in CI/Jobs even when these human-readable tags are recorded.

Use the exact GKE/Kubernetes benchmark profile that matches the running control plane and node version; record skipped or unsupported controls. A cluster scan that installs a Job or requires privileged/node filesystem access is not read-only: inspect its manifests/RBAC and obtain approval before running it. Do not grant cluster-admin to scanners for convenience.

## Pod Security Admission and workloads

PSA `restricted` is the default target for application namespaces. First run server-side dry-run/admission warning/audit to enumerate incompatible pods. Set the `enforce-version` label to the approved Kubernetes minor rather than a moving value. Use `baseline` only for a documented workload requirement and time-bound exception.

Restricted workloads should run as non-root, disable privilege escalation, drop all Linux capabilities, use `RuntimeDefault` seccomp, avoid host namespaces/hostPath, and set resource requests. Disable automatic service-account token mounts unless the workload calls the Kubernetes API. See `infra-kubernetes-workload-manage` for the deployment template.

## RBAC and identity

- Prefer namespace `Role`/`RoleBinding` over cluster-wide bindings and use named resources/verbs rather than `*`.
- Do not grant secret `list`/`watch`, `pods/exec`, `impersonate`, `bind`, or `escalate` without a specific approved need.
- Audit cluster-admin bindings and service-account token audiences; remove unused bindings through owner-approved changes.
- On GKE, use Workload Identity Federation instead of service-account keys; bind only the workload identity to its required cloud resource.

```bash
kubectl auth can-i --list --as="system:serviceaccount:${NAMESPACE}:${KSA}" -n "$NAMESPACE"
kubectl get clusterrolebindings -o json | jq -r \
  '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name + " -> " + ([.subjects[]?.name] | join(","))'
```

## Network and supply chain

Use an enforcing CNI and default-deny ingress/egress in application namespaces, then add narrowly scoped DNS, gateway, and service dependencies. Confirm policy behavior with flow logs or an approved test pod before enforcement. GKE Dataplane V2 supports native NetworkPolicy enforcement.

Require image digests from approved Artifact Registry repositories and verify signatures/attestations with the platform’s admission control. Scan images at build time and before deploy; do not rely on a tag or scan report alone as provenance proof.

## GKE control plane and data protection

- Prefer private nodes/control plane, authorized admin networks, Shielded nodes, release channels, controlled auto-upgrades, and a dedicated node identity.
- Encrypt Kubernetes secrets at rest with Cloud KMS where required; use Secret Manager/External Secrets or CSI for application secrets.
- Enable control-plane, admin, and workload audit logs and route them to a policy-approved sink with retention and access controls.
- Test cluster and persistent-volume backup/restore. Treat node pool replacement and version upgrades as maintenance events.

## Remediation workflow

1. Save the finding identifier, asset, affected namespace, and evidence with sensitive values redacted.
2. Map the finding to an owner and control; distinguish GKE-managed control planes from customer-managed resources.
3. Propose the smallest change, show dry-run/plan and workload impact, and secure approval.
4. Roll out to a non-production namespace/cluster first, then enforce gradually and monitor.
5. Re-scan using the same pinned version/profile and record any accepted exception with owner and expiry.

Never apply automated “fix” output from a scanner directly to a production cluster.

## References

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) — checked 2026-10-28.
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) — checked 2026-10-28.
- [GKE security overview](https://cloud.google.com/kubernetes-engine/docs/concepts/security-overview) — checked 2026-10-28.
- [kube-bench v0.16.0](https://github.com/aquasecurity/kube-bench/releases/tag/v0.16.0), [Kubescape v4.0.16](https://github.com/kubescape/kubescape/releases/tag/v4.0.16), [Trivy v0.76.1](https://github.com/aquasecurity/trivy/releases/tag/v0.76.1) — checked 2026-10-28.