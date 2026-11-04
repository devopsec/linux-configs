# cert-manager on GKE

This reference covers in-cluster issuance and renewal. Google Certificate Manager for load balancers and VM certbot deployments are separate systems and are intentionally not included here.

## Pin and install

cert-manager release `v1.21.3` was the current release checked on 2026-10-28. cert-manager `1.20+` requires Kubernetes `1.32+`; confirm the cluster meets that minimum before install. Pin the Helm CLI to `4.3.1` and use the matching cert-manager chart version.

```bash
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.3 --namespace cert-manager --create-namespace \
  --set crds.enabled=true --set prometheus.enabled=true \
  --rollback-on-failure --wait
kubectl -n cert-manager get pods
cmctl check api
```

Keep CRD upgrades separate from application deployment. Verify chart provenance/signature and key fingerprint according to the official project instructions before install. Pin `cmctl` to `v1.21.3` if used.

## Cloud DNS ACME issuer

Use GKE Workload Identity Federation; never create a service-account key. Grant DNS permissions only to the managed zone/required project scope, then bind the Google identity to the cert-manager Kubernetes service account. Do not grant project-wide `roles/dns.admin` when a narrower custom role is practical.

The YAML below contains `${...}` placeholders and is not ready to apply directly. Render it from approved project values or replace every placeholder and validate before applying.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: acme-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${OPERATIONS_EMAIL}
    privateKeySecretRef:
      name: acme-staging-account
    solvers:
      - dns01:
          cloudDNS:
            project: ${DNS_PROJECT_ID}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: acme-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${OPERATIONS_EMAIL}
    privateKeySecretRef:
      name: acme-production-account
    solvers:
      - dns01:
          cloudDNS:
            project: ${DNS_PROJECT_ID}
```

Start with the staging issuer. Verify DNS zone ownership, TXT record propagation, and a test Certificate before changing a production issuer. Keep the ACME account key in the namespace secret managed by cert-manager; never commit it.

## Certificate resource

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: api-certificate
  namespace: ${NAMESPACE}
spec:
  secretName: api-tls
  issuerRef:
    name: acme-production
    kind: ClusterIssuer
  dnsNames:
    - ${SERVICE_FQDN}
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always
```

For ACME, leave `duration` and `renewBefore` unset unless there is a validated reason; cert-manager should follow CA lifetime and renewal behavior. Restrict who can read the resulting TLS Secret. Apply ingress/gateway references only through their owning chart or overlay.

## Internal CA and monitoring

Use a CA issuer only when an approved internal CA keypair is already provisioned securely. Restrict the issuer and secret to the intended namespace; never commit CA private keys.

Alert on certificate readiness and expiry; retain Prometheus metrics and route alerts to the owning service team. Example expiry expression:

```promql
certmanager_certificate_expiration_timestamp_seconds - time() < 10 * 24 * 3600
```

Inspect `Certificate`, `CertificateRequest`, `Order`, and `Challenge` events/status with `kubectl describe` in the target namespace. Do not print private key Secret data while troubleshooting.

## References

- [cert-manager v1.21.3 release](https://github.com/cert-manager/cert-manager/releases/tag/v1.21.3) — checked 2026-10-28.
- [cert-manager installation](https://cert-manager.io/docs/installation/helm/) and [DNS-01 CloudDNS](https://cert-manager.io/docs/configuration/acme/dns01/google/) — checked 2026-10-28.
- [GKE Workload Identity Federation](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) — checked 2026-10-28.