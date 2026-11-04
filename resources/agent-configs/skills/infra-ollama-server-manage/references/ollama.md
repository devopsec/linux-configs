# Ollama single-host inference

Version checked 2026-10-28: Ollama `v0.40.12` (stable upstream release). Pin both the server and image tag; record a model digest or immutable model revision for production use.

## Install from a verified release asset

Do not use the upstream convenience installer in an unattended deployment. The Linux release archive publishes a SHA-256 manifest:

```bash
VERSION="v0.40.12" &&
# Set ARCH to amd64, arm64, or the approved GPU-specific asset.
ARCH="amd64" &&
BASE="https://github.com/ollama/ollama/releases/download/${VERSION}" &&
WORK='' &&
trap '[[ -z "$WORK" ]] || rm -rf "$WORK" || true' EXIT &&
WORK="$(mktemp -d)" &&
curl \
    --fail --silent --show-error --location \
    --output "${WORK}/ollama-linux-${ARCH}.tar.zst" \
    "${BASE}/ollama-linux-${ARCH}.tar.zst" &&
curl \
    --fail --silent --show-error --location \
    --output "${WORK}/sha256sum.txt" \
    "${BASE}/sha256sum.txt" &&
grep --extended-regexp \
    "^[[:xdigit:]]{64}  ollama-linux-${ARCH}.tar.zst$" \
    "${WORK}/sha256sum.txt" \
    > "${WORK}/asset.sha256" &&
(cd "$WORK" && sha256sum --check asset.sha256) &&
tar --zstd --extract --file="${WORK}/ollama-linux-${ARCH}.tar.zst" --directory=/usr/local &&
ollama --version
```

Run the extraction step through the host's approved privileged maintenance process. Install `zstd` from the OS package manager first. Also pin container images by digest after signature/provenance review; do not treat a mutable tag as an immutable artifact.

## Service and API boundary

Run as a dedicated non-login user with a dedicated model directory. Set `OLLAMA_HOST=localhost:11434`, restrict write access to the model store, and apply host service hardening (`NoNewPrivileges`, `ProtectSystem=strict`, a narrowly scoped writable path). On SELinux hosts, label a nonstandard model directory persistently rather than disabling SELinux.

Example `/etc/systemd/system/ollama.service`:

```ini
[Unit]
Description=Ollama LLM server
After=network-online.target
Wants=network-online.target

[Service]
User=ollama
Group=ollama
ExecStart=/usr/local/bin/ollama serve
Environment=OLLAMA_HOST=localhost:11434
Environment=OLLAMA_MODELS=/var/lib/ollama/models
Environment=OLLAMA_NUM_PARALLEL=2
Environment=OLLAMA_MAX_LOADED_MODELS=1
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/ollama
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Create the service user and model directory through the host's approved account process, then reload/enable the unit through the normal service-management workflow.

Ollama does not provide authentication. For remote access, use an authenticated TLS reverse proxy or LLM gateway, allow only the proxy's private network path, and keep the daemon listener private. Never bind all interfaces on a publicly reachable host.

## Operate and tune

```bash
ollama pull '<model>:<approved-tag>' &&
ollama list &&
ollama ps &&
curl -fsS http://localhost:11434/api/tags
```

For an OpenAI-compatible local client, use base URL `http://localhost:11434/v1`; an API key supplied to Ollama is not server-side authentication. Keep model/system prompts in reviewed configuration, not credentials or private data.

| Setting | Effect / guardrail |
|---|---|
| `OLLAMA_NUM_PARALLEL` | More concurrent requests; KV/context memory rises with concurrency. |
| `OLLAMA_MAX_LOADED_MODELS` | Models resident in memory; lower it when VRAM/RAM is constrained. |
| `OLLAMA_FLASH_ATTENTION` | Attention implementation; validate support on the selected device. |
| `OLLAMA_KEEP_ALIVE` | Model unload delay; bound it to control memory residency. |
| `CUDA_VISIBLE_DEVICES` | Select visible NVIDIA devices; verify with `nvidia-smi`. |

## Validate and troubleshoot

Run one health request and one representative generation; record latency, tokens/s, memory, GPU utilization, and model revision. For CPU fallback, check device visibility/driver/runtime; for OOM, reduce model quantization, context, loaded models, or parallel requests. For slow cold starts, pre-stage weights on persistent storage. Confirm free disk before pulling large models or deleting model caches.