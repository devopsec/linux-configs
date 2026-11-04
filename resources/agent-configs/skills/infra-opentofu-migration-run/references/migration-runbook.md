# Terraform to OpenTofu migration runbook

OpenTofu `1.13.2` is the exact CLI version checked on 2026-10-28. Pin the runtime in the project’s toolchain/CI image and record the Terraform source version as well. Keep the provider lock file, backend, workspace, and resource ownership unchanged during the first migration pass.

## 1. Inventory and baseline

Record:

- Terraform/OpenTofu CLI versions and required version constraints.
- Provider source addresses, exact locked versions, checksums, and provider aliases.
- Modules, provisioners, backend type, workspace/key, encryption settings, and any platform-specific features.
- CI runner identity, permissions, approval gates, saved-plan handling, and concurrency controls.
- Current state snapshot/remote backend version and an authorized recovery procedure.

Run the Terraform baseline from the normal controlled environment. Review and retain plan evidence securely; plans and state can contain sensitive values. Do not run a refresh/apply as part of inventory.

## 2. Feature and provider compatibility

OpenTofu can read many Terraform configurations and state files, but feature parity is not universal. Check every feature actually used—including encryption, provider functions, test mocks, dynamic backend/module configuration, and provider-specific write-only arguments—against OpenTofu `1.13.2` and the selected provider version. A successful parse is not proof that the plan is equivalent.

Preserve provider source addresses and `.terraform.lock.hcl`. Do not delete the lockfile or use `-upgrade` during the runtime switch. If a provider or platform checksum must change, handle that in a separate reviewed update and explain the exact lockfile diff.

## 3. Isolated plan-only test

Use a non-production clone/workspace or copied state where feasible. Verify no other process can change the same state, then run:

```bash
tofu version
tofu init -input=false
tofu validate
tofu plan -input=false -out=tofu-migration.tfplan
tofu show tofu-migration.tfplan
```

Use backend configuration and workspace values identical to the baseline. Do not print state or plan JSON into public logs. Compare planned actions, resource addresses, provider versions, and sensitive diffs against the Terraform baseline. An unexpected destroy/replace, changed identity, or unreadable state is a stop condition.

## 4. State and backend safety

Prefer backend-native versioning/snapshots and a tested recovery path. If a state file must be exported, treat it as secret-bearing data: write it only to an approved encrypted location with restrictive permissions, record the checksum and owner, and remove it only under the project’s approved retention process.

Do not run Terraform and OpenTofu concurrently against the same remote state. Do not change the backend or state encryption while switching the executable. Backend migration is a separate operation with its own copy, integrity verification, lock check, and explicit approval.

## 5. CI cutover and rollback

Change only the executable and tool setup after the isolated plan matches. Pin the CI image/action to OpenTofu `1.13.2`; retain separate validate/plan/apply permissions, protected production approvals, serialized state operations, and plan artifact integrity. Never use unattended auto-approval for a production cutover.

Keep the previous Terraform pipeline configuration and backend snapshot available until an approved OpenTofu run completes and the resulting infrastructure is verified. If the plan diverges, revert the tool-only CI change and investigate; do not fix drift by applying either plan blindly.

## References

- [OpenTofu 1.13.2 release](https://github.com/opentofu/opentofu/releases/tag/v1.13.2) — published 2026-10-21; checked 2026-10-28.
- [OpenTofu migration documentation](https://opentofu.org/docs/intro/migration/) — checked 2026-10-28.
- [OpenTofu state encryption](https://opentofu.org/docs/language/state/encryption/) — checked 2026-10-28.