---
name: infra-azure-vm-manage
description: "Provision and operate Azure Linux/Windows virtual machines, VM Scale Sets, managed disks, snapshots, Compute Gallery images, and Trusted Launch with Azure CLI and Terraform/OpenTofu. Use when requests mention Azure VM, VMSS, managed disk, cloud-init, Trusted Launch, Bastion, or Compute Gallery."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-azure/azure-vms
  license: MIT
---

# Azure VM manage

Use this skill for Azure compute resources and guest bootstrap. Keep network policy and image pipeline implementation with the related specialist skills.

## Triggers

- Create, resize, patch, access, or troubleshoot Azure VMs and VM Scale Sets.
- Configure managed disks, snapshots, cloud-init, Trusted Launch, or availability zones.
- Create or deploy a Compute Gallery image.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/azure-vm.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/azure-vm.toml"
ELSE use the defaults listed below
IF task involves Azure VMs, VMSS, disks, images, or guest bootstrap
  REFERENCE "references/vms.md"
CACHE only the loaded VM guidance for this task
```

## Workflow

1. Inspect subscription, tenant, region, resource group, resource ownership, quota, and SKU/zone availability read-only; confirm the target environment.
2. Prefer Terraform/OpenTofu for managed resources and a signed, package-managed Azure CLI for inspection. Use private networking, managed identity, Trusted Launch, and encrypted disks by default.
3. Check deallocation/restart effects, guest access, disk persistence, image compatibility, capacity, and cost before planning.
4. Require explicit confirmation for VM deletion, deprovisioning, disk replacement, or production rollout; snapshot critical data and verify backup coverage first.
5. Verify VM/VMSS health, guest boot diagnostics, update status, and access through the selected private access path.

### Defaults when no config exists

- Azure CLI `2.91.0` and AzureRM provider `5.11.0` (checked 2026-10-28); pin provider and module constraints in the IaC lock/configuration.
- Terraform/OpenTofu with Azure Verified Modules where suitable; Azure CLI for inspection and bootstrap.
- Ask for subscription, region, VM SKU, image version, network, and maintenance requirements when missing.

## Related skills

- Azure networking → `infra-azure-network-manage`
- Azure image pipeline → `infra-packer-azureImage-build`
- IaC and AVM workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`, `infra-terraform-avmModule-develop`
- Guest OS hardening and SSH → `sec-linux-host-harden`, `infra-linux-ssh-manage`
