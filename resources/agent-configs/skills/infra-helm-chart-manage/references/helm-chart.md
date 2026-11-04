# Helm chart authoring and releases

Helm CLI `4.3.1` was the latest stable release checked on 2026-10-28. Pin the CLI in the repository toolchain/CI image and test chart/plugin compatibility before upgrades. Keep chart `version`, application version, image digest, and Kubernetes API version explicit.

## Chart structure and templates

```text
chart/
  Chart.yaml
  Chart.lock
  values.yaml
  values.schema.json
  templates/_helpers.tpl
  templates/deployment.yaml
  templates/service.yaml
```

`values.yaml` contains non-secret defaults only. Use `values.schema.json` to validate required values and types. Keep templates deterministic and use selectors that remain stable across updates. Use `required` for mandatory settings, quote strings, and render `toYaml` with the correct indentation. Bump chart SemVer for every chart change; `appVersion` describes the application release, not the chart.

## Lint, render, and validate

```bash
helm lint ./chart -f "$VALUES_FILE"
helm dependency build ./chart
helm template "$RELEASE" ./chart --namespace "$NAMESPACE" -f "$VALUES_FILE" > rendered.yaml
kubectl apply --dry-run=server -f rendered.yaml
```

Review the rendered manifest for public services, RBAC, selectors, CRDs, hooks, secret values, and resource deletions. Keep `Chart.lock` committed and use the locked dependency build in CI; dependency updates are separate reviewed changes.

## Release and rollback

The optional `helm-diff` plugin `3.15.15` was the latest release checked on 2026-10-28. Verify its compatibility with Helm `4.3.1` in an isolated environment before enabling it; otherwise use the exact rendered manifest and server-side dry-run. Helm `4.3.1` uses `--rollback-on-failure`; do not copy Helm 3’s `--atomic` flag into a Helm 4 command.

```bash
helm upgrade --install "$RELEASE" ./chart -n "$NAMESPACE" \
  -f "$VALUES_FILE" --rollback-on-failure --wait --timeout 10m
helm history "$RELEASE" -n "$NAMESPACE"
helm get values "$RELEASE" -n "$NAMESPACE" --all
helm rollback "$RELEASE" "$REVISION" -n "$NAMESPACE" --wait
```

Upgrade, rollback, uninstall, hook execution, and CRD application mutate cluster state. Verify context, namespace, release ownership, and a rendered diff and obtain explicit approval. Uninstall is destructive; confirm retained data and resources first.

## OCI charts and secrets

Publish versioned OCI charts to the approved registry, with registry write permission limited to a publisher identity and pull permission limited to deployers. Never use mutable chart/image tags in production.

Never commit secret values in `values*.yaml`. Reference secret names from Secret Manager/External Secrets/CSI, or supply encrypted files through an approved SOPS/KMS process. Avoid secrets in `--set`, command history, or CI logs.

## CRDs and common issues

- Helm does not upgrade or delete CRDs placed in `crds/`; manage CRD upgrades separately with compatibility review.
- A pending release operation requires inspecting `helm history` and the deployed revision before recovery.
- Existing unowned objects require deliberate ownership transfer; do not delete them just to make an install pass.
- Values ignored: inspect `helm get values --all`, schema, and rendered output.

## References

- [Helm v4.3.1 release](https://github.com/helm/helm/releases/tag/v4.3.1) — published 2026-10-15; checked 2026-10-28.
- [helm-diff v3.15.15 release](https://github.com/databus23/helm-diff/releases/tag/v3.15.15) — published 2026-09-26; checked 2026-10-28.
- [Helm chart best practices](https://helm.sh/docs/chart_best_practices/) — checked 2026-10-28.