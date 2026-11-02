# Private LLM fine-tuning

## Contents

- Decide between prompting, RAG, and fine-tuning
- Locked TRL QLoRA SFT and Axolotl config examples
- Multi-GPU, DPO, and GKE job guidance
- Data governance, evaluation, and model registration

Versions checked 2026-10-28: Axolotl `0.21.0` and Hugging Face TRL `1.16.0`. Pin the complete CUDA/PyTorch/Transformers/PEFT environment in an immutable container or lockfile; the trainer and accelerator matrix must be compatible, not independently upgraded.

## Decide whether to fine-tune

| Need | Start with |
|---|---|
| Changing facts or private knowledge | RAG and a versioned index. |
| Output format or tone | Prompt/few-shot evaluation; then LoRA SFT if needed. |
| Preference alignment | SFT baseline, then DPO on reviewed preference pairs. |
| No GPU operations | Approved provider/Vertex tuning service, subject to data-processing review. |

## Inputs and environment

Before launch establish base model ID/revision/license, task objective, dataset provenance/classification, immutable dataset version/hash, evaluation split, GPU architecture/count, budget, output location, and retention. Begin with a small representative run. Keep packages and container digest pinned; use a locked `uv` environment for direct TRL work or the pinned Axolotl release/container for config-driven runs.

Example direct dependency pin:

```bash
uv add 'trl==1.16.0'
```

Read gated model tokens from a secret manager at runtime. Do not store tokens in notebooks, training configs, images, or shell history.

## QLoRA SFT example

Use an immutable base-model revision and a prevalidated train/eval split:

```python
import torch
from datasets import load_dataset
from peft import LoraConfig
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
from trl import SFTConfig, SFTTrainer

model_id = '<approved-model-id>'
revision = '<immutable-commit-sha>'
model = AutoModelForCausalLM.from_pretrained(
    model_id,
    revision=revision,
    device_map='auto',
    quantization_config=BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type='nf4',
        bnb_4bit_compute_dtype=torch.bfloat16,
        bnb_4bit_use_double_quant=True,
    ),
)
tokenizer = AutoTokenizer.from_pretrained(model_id, revision=revision)
data = load_dataset('json', data_files={'train': '<train.jsonl>', 'eval': '<eval.jsonl>'})
lora_config = LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05, task_type='CAUSAL_LM')
sft_trainer = SFTTrainer(
    model=model,
    processing_class=tokenizer,
    peft_config=lora_config,
    train_dataset=data['train'],
    eval_dataset=data['eval'],
    args=SFTConfig(output_dir='<private-output-dir>', num_train_epochs=3,
                   per_device_train_batch_size=2, gradient_accumulation_steps=8,
                   learning_rate=2e-4, bf16=True, eval_strategy='steps', eval_steps=100),
)
sft_trainer.train()
sft_trainer.save_model('<private-output-dir>/adapter')
```

Validate chat template/tokenization and a tiny batch before a costly full run. Tune rank, sequence length, micro-batch, gradient accumulation, and learning rate using held-out metrics and actual device memory.

## Axolotl config-driven run

Pin Axolotl and run preprocessing before GPU training. The full CUDA/PyTorch stack should come from a compatible lock or digest-pinned official container.

```yaml
base_model: <approved-model-id>
base_model_revision: <immutable-commit-sha>
load_in_4bit: true
adapter: qlora
lora_r: 16
lora_alpha: 32
lora_dropout: 0.05
chat_template: <model-chat-template>
datasets:
  - path: <private-train-jsonl>
    type: chat_template
val_set_size: 0.05
output_dir: <private-checkpoint-path>
sequence_len: 4096
micro_batch_size: 2
gradient_accumulation_steps: 8
num_epochs: 3
learning_rate: 0.0002
bf16: true
eval_steps: 100
save_steps: 200
```

```bash
uv add 'axolotl[flash-attn,deepspeed]==0.21.0' &&
axolotl preprocess config.yaml &&
axolotl train config.yaml
```

## Multi-GPU and DPO

## Multi-GPU and DPO

Use DeepSpeed ZeRO-3 or FSDP when a measured memory limit requires sharding; choose one strategy and test checkpoint/restart. CPU offload saves VRAM but can reduce throughput substantially. DPO data must contain reviewed `prompt`, `chosen`, and `rejected` pairs; verify preference data is not present in the evaluation set.

```python
from peft import LoraConfig
from trl import DPOConfig, DPOTrainer

dpo_trainer = DPOTrainer(
    model=sft_trainer.model,
    ref_model=None,
    processing_class=tokenizer,
    peft_config=lora_config,
    train_dataset=preference_data['train'],
    args=DPOConfig(output_dir='<private-dpo-output>', beta=0.1, num_train_epochs=1,
                   per_device_train_batch_size=1, gradient_accumulation_steps=16,
                   learning_rate=5e-7, bf16=True),
)
dpo_trainer.train()
```

With PEFT, `ref_model=None` uses the adapter-disabled base as the reference. Checkpoint to private persistent storage, especially on spot GPUs.

## GKE training job

For a GKE run, use Workload Identity for dataset/model buckets and an image digest that contains the locked Axolotl environment. Confirm GPU class/quota and scratch capacity before creating the job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: <training-job>
  namespace: <namespace>
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: OnFailure
      serviceAccountName: <trainer-workload-identity>
      nodeSelector: {cloud.google.com/gke-accelerator: <gpu-class-label>}
      containers:
        - name: trainer
          image: <region>-docker.pkg.dev/<project>/<repo>/axolotl@sha256:<image-digest>
          command: ["axolotl", "train", "/config/config.yaml"]
          resources:
            requests: {nvidia.com/gpu: "1", memory: <memory-limit>}
            limits: {nvidia.com/gpu: "1", memory: <memory-limit>}
```

Use a checkpoint/PVC or versioned GCS output, bounded retry, and a job-specific identity. For managed custom training, consider Vertex AI or Cloud Batch through `infra-ml-pipeline-orchestrate`.

## Data governance, evaluation, and registration

- Classify/de-identify personal data, remove secrets, deduplicate, and reserve a held-out set that is never trained on.
- Store checkpoints and merged models in private versioned storage; checkpoint before spot interruption and test resume.
- Gate registration on task-specific held-out metrics, regression prompts, safety/refusal checks, and latency/model-size limits. Use `dev-agents-evals-create` for evaluation harness design.
- Record base model/revision, dataset hash, trainer/container digest, config, metrics, artifact digest, and applicable model/data licenses in a model card.
- Merge LoRA into full-precision/BF16 weights only when required; preserve a tested adapter artifact for rollback. Publish externally only with explicit approval.

For deployment and serving configuration, hand off to `infra-vllm-server-manage` or `infra-kserve-modelServing-manage`; for orchestration use `infra-ml-pipeline-orchestrate`.