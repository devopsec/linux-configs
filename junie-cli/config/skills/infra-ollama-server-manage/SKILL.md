---
name: infra-ollama-server-manage
description: "Install and operate Ollama for local or private single-host inference, including model storage, systemd, API access, and GPU troubleshooting. Use when a request mentions Ollama, `ollama serve`, local GGUF models, port 11434, or a private Ollama endpoint."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/local-ai/ollama-stack]
  license: MIT
---

# Ollama server management

## Triggers

- Install, upgrade, or configure Ollama on a developer host or private VM.
- Operate Ollama models, local API clients, systemd, or GPU-backed inference.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/ollama.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/ollama.toml"
ELSE
  use the defaults below and in "references/ollama.md"
REFERENCE "references/ollama.md" for install, service, model, or troubleshooting work
CACHE only the loaded Ollama guidance
```

## Workflow

1. Confirm host OS/architecture, GPU, model license/revision, and whether callers are local or on a private network.
2. Pin Ollama `v0.40.12` (checked 2026-10-28); use a verified release archive or immutable image, never a shell-piped installer.
3. Bind to loopback by default, run as a restricted service account, and keep model data on its dedicated volume.
4. Smoke-test health and one representative prompt; inspect GPU use, memory, and model-load behavior.
5. Record the selected model revision and rollback path before changing a shared host.

## Defaults

- Ollama `v0.40.12`; bind `localhost:11434`, use a dedicated non-login user and host-managed model store.
- Assume no built-in auth; remote requests must pass through an authenticated TLS gateway.

## Safety

- Ollama has no built-in authentication. Never expose port `11434` publicly; use an authenticated TLS gateway for remote access.
- Do not put credentials, production prompts, or customer data in model files or logs.
- A model pull or storage cleanup can consume significant bandwidth/disk; confirm target and available space first.

## Related skills

- vLLM inference serving → `infra-vllm-server-manage`
- LLM routing, keys, and budgets → `infra-llm-gateway-manage`
- Host service management → `infra-linux-systemd-manage`

## Reference

- Ollama lifecycle, hardening, and troubleshooting: [references/ollama.md](references/ollama.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
