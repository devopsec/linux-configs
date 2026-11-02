# Container hardening

## Image

- Minimal base: distroless, slim, or UBI-minimal where compatible; select an approved image and pin the release image by digest.
- Rebuild regularly for base CVE fixes while retaining the approved digest for each release.
- Non-root numeric `USER 10001:10001` (numeric lets k8s `runAsNonRoot` verify).
- No package managers/shells/compilers in the final stage (multi-stage).
- No secrets in layers — check with `docker history --no-trunc` and a secret scanner; a later `RUN rm` does **not** remove an earlier layer.
- Labels: `org.opencontainers.image.source`, `.revision` (git SHA), `.version`.
- Lint `hadolint`; scan `trivy image --severity HIGH,CRITICAL --exit-code 1 "$IMG"` or `grype "$IMG" --fail-on high`.

## Runtime (Docker / Podman flags)

```bash
docker run -d \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --user 10001:10001 \
  --cap-drop=ALL \
  --security-opt=no-new-privileges:true \
  --pids-limit=256 --memory=512m --cpus=1 \
  "$IMG@sha256:<digest>"
```

- Add back only needed caps: `NET_BIND_SERVICE` (ports <1024), `NET_ADMIN`/`SYS_NICE` only if an RTP relay demonstrably needs them — document why.
- Keep default seccomp/AppArmor/SELinux profiles; never `--privileged` or `seccomp=unconfined` in production.
- Do not mount `docker.sock`/`podman.sock`, host `/`, `/proc`, or `/sys` read-write.
- Daemon: `userns-remap` in `/etc/docker/daemon.json` or use rootless Podman; `"live-restore": true`; log rotation.

Kubernetes pod security contexts and cluster policy → `sec-kubernetes-cluster-harden`.

## Checklist

- [ ] Minimal, digest-pinned base; multi-stage
- [ ] Non-root numeric user
- [ ] Read-only rootfs + tmpfs for scratch
- [ ] `cap-drop ALL`, `no-new-privileges`, default seccomp
- [ ] Resource limits (memory, cpu, pids)
- [ ] No secrets in image/env files committed; Secret Manager / runtime secrets
- [ ] Scan in CI (fail on HIGH/CRITICAL with documented exceptions)
- [ ] Sign digest (cosign) and verify at deploy
- [ ] Ports bound to specific interfaces; GCP firewall restricts sources
- [ ] Logs to stdout/journald → Cloud Logging
