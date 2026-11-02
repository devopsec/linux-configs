# Podman (rootless, Quadlet, RHEL)

Daemonless and Docker-CLI compatible. Use the supported distribution package and record the installed version for host reproducibility; RHEL-family systems commonly default to Podman.

| | Docker | Podman |
|---|---|---|
| Daemon | `dockerd` (root) | none (fork/exec, conmon) |
| Rootless | optional | first-class |
| Pods | no | yes (k8s-style, shared netns) |
| systemd | external unit | Quadlet generator (native) |
| API socket | `docker.sock` | `podman.socket` (opt-in) |

## Rootless setup

```bash
grep "^$USER:" /etc/subuid /etc/subgid          # confirm configured subordinate ranges
usermod --add-subuids <approved-start>-<approved-end> --add-subgids <approved-start>-<approved-end> "$USER"   # as root, only when approved ranges are missing
podman system migrate                            # after changing subuid/subgid
podman unshare cat /proc/self/uid_map            # verify mapping
loginctl enable-linger "$USER"                   # keep user services running without login
```

- Rootless cannot bind ports below the host's unprivileged-port threshold. Prefer an approved high-port mapping and firewall forward; changing the host threshold is a system-wide security decision.
- Rootless networking uses the configured backend; select host networking only when the workload requires source/port behavior that cannot be preserved otherwise, and document the privilege impact.
- Storage: `~/.local/share/containers/storage` (rootless), `/var/lib/containers/storage` (rootful).

## SELinux volume labels

```bash
podman run -v ./data:/app/data:Z myapp     # private label (one container)
podman run -v ./shared:/shared:z myapp     # shared label (several containers)
```
Never `:Z` a system directory (`/etc`, `/home`, `/var/lib/...` of other services) — it relabels it. Use `--security-opt label=disable` only as a last, documented resort.

## Quadlet (systemd-native)

Locations: rootful `/etc/containers/systemd/`, rootless `~/.config/containers/systemd/`.

```ini
# /etc/containers/systemd/myapp.container
[Unit]
Description=myapp
After=network-online.target
Wants=network-online.target

[Container]
Image=REGION-docker.pkg.dev/PROJECT/REPO/myapp@sha256:<digest>
ContainerName=myapp
PublishPort=127.0.0.1:8080:8080
Volume=myapp-data.volume:/var/lib/myapp:Z
EnvironmentFile=/etc/myapp/myapp.env
Secret=myapp-db-password,type=env,target=DATABASE_PASSWORD
User=10001
ReadOnly=true
NoNewPrivileges=true
DropCapability=ALL
AutoUpdate=registry
HealthCmd=/app/.venv/bin/python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=3)"
HealthOnFailure=kill

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

```bash
/usr/libexec/podman/quadlet -dryrun              # render units, show errors (add -user for rootless)
systemctl daemon-reload
systemctl start myapp.service                     # generated units cannot be `enable`d; [Install] handles it
journalctl -u myapp.service -f
podman auto-update --dry-run                      # with AutoUpdate=registry
```

Other Quadlet types: `.volume`, `.network`, `.pod`, `.kube` (runs `podman kube play`), `.image`, `.build`.
Secrets: `printf '%s' "$VALUE" | podman secret create myapp-db-password -` (value from Secret Manager at provision time, not in the unit).

## Pods and kube YAML

```bash
podman pod create --name stack -p 127.0.0.1:8080:8080
podman run -d --pod stack --name db postgres@sha256:<approved-digest>
podman run -d --pod stack --name app myapp      # reaches db via localhost
podman kube generate stack > stack.yaml          # export as k8s YAML
podman kube play stack.yaml; podman kube down stack.yaml
```

## Registries & auth

`/etc/containers/registries.conf` (or `~/.config/containers/registries.conf`):

```toml
unqualified-search-registries = ["docker.io"]
short-name-mode = "enforcing"          # avoid ambiguous short-name pulls

[[registry]]
prefix = "docker.io"
location = "docker.io"
[[registry.mirror]]
location = "mirror.gcr.io"
```

Auth file: `${XDG_RUNTIME_DIR}/containers/auth.json` (rootless). Use `infra-gcp-artifactRegistry-manage` for Artifact Registry authentication and IAM.

## Buildah

`podman build` uses Buildah. `--format docker` when a registry/runtime needs Docker manifest (e.g. `HEALTHCHECK` is dropped in OCI format). Scratch images: `buildah from scratch` → `buildah copy` → `buildah config --entrypoint` → `buildah commit`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `permission denied` on bind mount | SELinux label `:Z`/`:z`; check `ls -Z`; UID mapping (`podman unshare chown`) |
| User service dies at logout | `loginctl enable-linger` |
| Port <1024 refused (rootless) | high port + firewalld forward, or rootful unit |
| `short-name resolution` prompt/error | fully-qualify image (`docker.io/library/nginx`) |
| Quadlet unit missing | `quadlet -dryrun` output; file extension; `daemon-reload` |
