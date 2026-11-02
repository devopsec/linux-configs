# Kustomize bases and overlays

Standalone Kustomize `5.8.3` and Kubeconform `v0.8.0` were the latest releases checked on 2026-10-28. `kubectl` also embeds Kustomize; its renderer version follows the chosen kubectl binary. Use the cluster-compatible kubectl build unless the overlay requires a feature unavailable there.

## Layout and API

```text
deploy/
  base/kustomization.yaml
  base/deployment.yaml
  base/service.yaml
  overlays/dev/kustomization.yaml
  overlays/prod/kustomization.yaml
```

Use `resources` and `patches`; do not introduce deprecated `bases`, `commonLabels`, `patchesStrategicMerge`, or `patchesJson6902`. Do not mutate workload selectors when adding common labels; set `includeSelectors: false` unless creating a new resource.

Every `${...}` value below is a descriptive placeholder: Kustomize does not expand shell environment variables in YAML. Replace all placeholders with validated values before rendering or applying.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: ${NAMESPACE}
labels:
  - pairs:
      app.kubernetes.io/name: ${APP_NAME}
    includeSelectors: false
images:
  - name: ${IMAGE_NAME}
    newName: ${IMAGE_REGISTRY_PATH}
    digest: sha256:${IMAGE_DIGEST}
patches:
  - path: resources.patch.yaml
```

Keep remote bases pinned to immutable tags/commits. Prefer a structured patch targeting kind/name rather than a broad JSON path tied to list ordering. Use `components` only when the same optional behavior can be shared safely across overlays.

## Render, validate, and apply

```bash
kubectl kustomize "$OVERLAY" > rendered.yaml
kubeconform -strict -summary rendered.yaml  # Kubeconform v0.8.0; pin schema source/version in CI.
kubectl diff -k "$OVERLAY"
```

Review the rendered output for namespaces, selectors, image digests, RBAC, public services, secret references, and deleted resources. `kubectl diff` is a preview; a nonzero difference status is not automatically a validation failure. Apply only after explicit approval:

```bash
kubectl apply -k "$OVERLAY" --server-side
```

Avoid `--prune` unless an explicit label scope and deletion review are in place. Kustomize `secretGenerator` with literal/file values can store secret material in Git; use SOPS/KMS, External Secrets, or Secret Manager CSI instead.

## Common issues

- Immutable selector errors: exclude selector mutation from label transformers or plan a controlled recreation.
- A patch misses: confirm target kind/name after name prefix/suffix transformations.
- Generated ConfigMaps use hash suffixes; dependent pods should update through the rendered name.
- Restrict load roots to the repository tree; do not disable load restrictions in CI.

## References

- [Kustomize v5.8.3 release](https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize%2Fv5.8.3) — checked 2026-10-28.
- [Kubeconform v0.8.0 release](https://github.com/yannh/kubeconform/releases/tag/v0.8.0) — checked 2026-10-28.
- [Kustomize documentation](https://kubectl.docs.kubernetes.io/references/kustomize/) — checked 2026-10-28.