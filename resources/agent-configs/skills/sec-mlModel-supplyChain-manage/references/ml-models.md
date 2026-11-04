# ML model artifact integrity

## Threats and safe formats

Model weights, adapters, conversion tools, registries, and serving images can be poisoned or substituted. Prefer `safetensors`, ONNX, or GGUF. Treat `.pt`, `.pkl`, `.bin`, and joblib artifacts as executable inputs; never deserialize untrusted pickle data in a trusted process. If PyTorch is required, use `weights_only=True` where compatible and convert untrusted artifacts in an isolated sandbox.

## Source pinning and scan

Record the repository, immutable revision/commit, license, model card, and expected file digests. Do not download from a mutable branch/name for a production promotion. PickleScan `1.0.5` was the latest PyPI project page version checked on `2026-10-28`; pin that release in the project toolchain and run it in an isolated environment:

```bash
uvx picklescan==1.0.5 --path "${MODEL_DIRECTORY}"
```

Do not load model weights during scanning. Keep proprietary weights and reports local unless external scanning is authorized.

## Integrity, provenance, and promotion

Hash the exact bytes that will be deployed, sign the digest or a manifest, and attach a provenance/model card containing source revision, training code, dataset identifiers, conversion steps, evaluator results, and artifact digests. Use `sec-artifact-sbom-sign` for Cosign signing and verification details. Verify evidence again after registry upload because a transformation changes the bytes.

Promote dev → staging → production only after signature, scan, licensing, and evaluation policies pass. Enforce the policy in the release/deploy step, fail closed on missing evidence, and mount model files read-only in serving workloads. Restrict outbound network access unless the serving design requires it.