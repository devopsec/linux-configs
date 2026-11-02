---
name: sec-mlModel-supplyChain-manage
description: "Protect machine-learning model artifacts from unsafe formats, poisoned or substituted weights, untrusted registries, and pipeline tampering. Use when a task mentions model weights, Hugging Face revisions, pickle/safetensors, model promotion, model signatures, or artifact integrity."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/ai/model-supply-chain-security]
  license: MIT
---

# ML model supply chain manage

Treat model weights, adapters, conversion tools, and registries as supply-chain inputs that require provenance and integrity checks.

## Triggers

- Download, scan, promote, or deploy model weights/adapters.
- Review pickle-based formats, model source revisions, or model artifact signing.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/security/ml-models.toml" exists
  REFERENCE "~/.junie/custom/configs/security/ml-models.toml"
ELSE
  REFERENCE "assets/config.example.toml"
  REFERENCE "references/ml-models.md" for defaults
CACHE only the model format, source pin, or promotion policy needed
```

## Workflow

1. Record model source, immutable revision, license, artifact digest, conversion pipeline, and intended consumer.
2. Prefer `safetensors`, ONNX, or GGUF; do not load untrusted pickle formats in a trusted process.
3. Scan artifacts with the configured pickle/model scanner in an isolated environment, then hash and sign the exact bytes.
4. Attach provenance/model-card metadata and verify the signature and digest before promotion.
5. Promote only after security scans and evaluation policy pass; keep runtime mounts read-only and outbound access constrained.

## Safety

- Keep model files and conversion utilities untrusted until scanned; never `pickle.load` arbitrary artifacts.
- Pin downloads to commit/release digests, not a mutable model name or branch.
- Do not upload proprietary weights or scan reports to public services without authorization.

## Related skills

- SBOM/signature infrastructure: `sec-artifact-sbom-sign`.
- Model serving and pipeline workflows: `infra-ml-pipeline-manage` and `infra-llm-platform-manage`.
- Image scanning: `sec-container-image-scan`.

## References

- [ML model artifact integrity](references/ml-models.md)
