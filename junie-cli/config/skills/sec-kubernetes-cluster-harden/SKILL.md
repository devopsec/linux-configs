---
name: sec-kubernetes-cluster-harden
description: "Assess and harden Kubernetes and GKE clusters using Pod Security Admission, RBAC, NetworkPolicy, image policy, encryption, audit controls, kube-bench, Kubescape, Trivy, and cert-manager. Use when requests mention Kubernetes security baseline, CIS Kubernetes scan, PSA restricted, cluster-admin audit, NetworkPolicy, GKE hardening, or cert-manager."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/hardening/kubernetes-hardening
    - security/network/ssl-tls-management
  license: MIT
---

# Kubernetes cluster harden

Assess authorized clusters and propose staged hardening. Default to report-only scans; do not apply policy or remediation automatically.

## Triggers

- Kubernetes security posture, GKE hardening, CIS benchmark, RBAC review, cluster-admin binding
- Pod Security Admission, NetworkPolicy, admission policy, image digest/signature, cert-manager

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md and security guidance if present
IF file exists "~/.junie/custom/configs/security/kubernetes.toml"
  REFERENCE "~/.junie/custom/configs/security/kubernetes.toml"
ELSE
  use kube-bench 0.16.0 with GKE profile in report-only mode; use Kubescape 4.0.16 or Trivy 0.76.1 only for the corresponding configured scan type
IF task involves cluster policy, RBAC, network isolation, image security, or scans
  REFERENCE "references/cluster-hardening.md"
IF task involves Kubernetes certificate issuance, ACME, Cloud DNS issuer, or certificate alerts
  REFERENCE "references/cert-manager.md"
IF task changes application workload security context or probes
  REFERENCE skill "infra-kubernetes-workload-manage"
IF task targets GKE node/control-plane configuration
  REFERENCE skill "infra-gcp-gke-manage"
CACHE authorized cluster/context, scope, Kubernetes version, scanner mode, and approved maintenance window
```

## Workflow

1. Confirm cluster ownership, authorization, context, namespace scope, target Kubernetes version, and whether scans may query the live API.
2. Run scanners in report-only/read-only mode with least-privilege identity; record tool versions and control coverage.
3. Prioritize findings by exposure and impact; distinguish platform-managed controls from customer-managed controls.
4. Propose one change at a time with a dry-run, impact, rollback, and user approval; never remediate scan findings autonomously.
5. Validate policy admission and workload compatibility in a non-production namespace before enforcement.
6. Re-scan and verify audit, policy, and certificate health after approved changes.

## Related skills

- `infra-gcp-gke-manage` — GKE cluster and node controls.
- `infra-kubernetes-workload-manage` — workload settings and diagnostics.
- `infra-serviceMesh-any-manage` — mesh mTLS and authorization.
- `sec-dev-threatModel-create` — threat model for cluster boundary changes.
