# Azure Virtual Machines — VMs, disks, images, VMSS

Golden images with Packer → `infra-packer-azureImage-build`.

## Contents
- CLI setup (no piped installers)
- Create Linux VM (RHEL-family / Ubuntu)
- Windows VM (no literal passwords)
- cloud-init
- Sizes
- Managed disks and snapshots
- Images and Compute Gallery
- Availability (zones, VMSS)
- Day-2 operations
- Terraform/OpenTofu (incl. AVM)
- Troubleshooting

## CLI setup

Use Azure CLI `2.91.0` (checked 2026-10-28) from Microsoft's signed package repository; pin that exact package version in the managed tool environment and confirm with `az version`:

```bash
# RHEL 9 / 10 — run as root (use the matching release path)
rpm --import https://packages.microsoft.com/keys/microsoft.asc
dnf install -y https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm
dnf install -y azure-cli-2.91.0
# Debian/Ubuntu: add the packages.microsoft.com apt repo with its signed-by keyring, then `apt-get install azure-cli`
```

```bash
az login                                    # humans; CI uses workload identity federation (see networking.md / functions.md)
az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
az group create --name <rg> --location <region> --tags environment=<env> team=<team>
```

## Create Linux VM

```bash
az vm image list --publisher RedHat --offer RHEL --sku 9-lvm-gen2 --all -o table | tail -3   # or Canonical ubuntu-24_04-lts
az vm create -g <rg> -n <vm> \
  --image RedHat:RHEL:9-lvm-gen2:<approved-image-version> \
  --size Standard_D4s_v5 --zone 1 \
  --admin-username <admin-user> --ssh-key-values @<public-key-file> \
  --vnet-name <vnet> --subnet <app-subnet> --nsg "" --public-ip-address "" \
  --os-disk-size-gb 64 --storage-sku Premium_LRS \
  --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true \
  --assign-identity '[system]' --encryption-at-host true \
  --custom-data cloud-init.yaml \
  --tags environment=<env> app=<app>
az vm extension set -g <rg> --vm-name <vm> --publisher Microsoft.Azure.ActiveDirectory --name AADSSHLoginForLinux
```

- No public IP; reach via Azure Bastion (`az network bastion ssh`) or Entra ID SSH (`az ssh vm -g <rg> -n <vm>`).
- `--nsg ""` means rely on the subnet NSG (see `networking.md`).
- Default outbound access for new VNets is retired (2025-09-30) — private subnets need a NAT Gateway / firewall for egress.
- RHEL on Azure: PAYG images include RHUI repos; BYOS needs subscription-manager. Keep SELinux enforcing; firewalld per `sec-network-perimeter-manage`.

## Windows VM

```bash
# Password comes from Key Vault into an env var at runtime; never inline it
WIN_ADMIN_PASSWORD="$(az keyvault secret show --vault-name <kv> --name <win-admin-secret> --query value -o tsv)"
az vm create -g <rg> -n <win-vm> --image Win2025Datacenter --size Standard_D4s_v5 --zone 1 \
  --admin-username <admin-user> --admin-password "${WIN_ADMIN_PASSWORD}" \
  --vnet-name <vnet> --subnet <app-subnet> --public-ip-address "" --security-type TrustedLaunch
unset WIN_ADMIN_PASSWORD
```

Prefer Entra ID login (`AADLoginForWindows` extension) + Bastion RDP afterwards; rotate the local admin password via LAPS.

## cloud-init

```yaml
#cloud-config
package_upgrade: true
packages: [chrony, firewalld]
write_files:
runcmd:
  - [systemctl, enable, --now, firewalld]
  # Bootstrap only the packages and services approved for this workload.
```

Logs: `/var/log/cloud-init-output.log`; `cloud-init status --long`. Custom data is not secret — fetch secrets from Key Vault with the VM's managed identity at boot.

## Sizes

| Family | Examples | Use |
|---|---|---|
| B (burstable) | B2s_v2, B4ls_v2 | dev, intermittent low CPU workloads |
| D (general) | D4s_v5/v6, D4ps_v6 (Arm) | general production workloads |
| F (compute) | F4s_v2, FX | compute-bound workloads, batch |
| E (memory) | E4s_v5 | PostgreSQL on VM, caches |
| L (storage) | L8s_v3 | local NVMe |
| N (GPU) | NC A100/H100 v5 | ML |

```bash
az vm list-skus --location <region> --size Standard_D4s_v5 --zone -o table   # zonal availability + restrictions
az vm list-usage --location <region> -o table                                # quota
```

Check regional SKU and zone availability before selecting a size; enable accelerated networking when supported and useful for the workload.

## Managed disks and snapshots

```bash
az vm disk attach -g <rg> --vm-name <vm> --name <vm>-data --new --size-gb 256 --sku PremiumV2_LRS --lun 0
az disk update -g <rg> -n <vm>-data --size-gb 512            # grow online for most disks; then grow FS inside guest
az snapshot create -g <rg> -n <vm>-data-$(date +%Y%m%d) --source <vm>-data --incremental true
az disk create -g <rg> -n <vm>-data-restore --source <snapshot-name> --zone 1
```

Premium SSD v2 for databases (IOPS/throughput independent of size, zonal only). Encryption: platform-managed by default; customer-managed keys via Disk Encryption Set + Key Vault.

## Images and Compute Gallery

```bash
# Inside the VM (DESTRUCTIVE for that VM: removes users/SSH keys):  waagent -deprovision+user -force
az vm deallocate -g <rg> -n <build-vm> && az vm generalize -g <rg> -n <build-vm>
az sig create -g <rg> --gallery-name <gallery>
az sig image-definition create -g <rg> --gallery-name <gallery> --gallery-image-definition <app> \
  --publisher <org> --offer <app> --sku <sku> --os-type Linux --os-state Generalized \
  --hyper-v-generation V2 --features SecurityType=TrustedLaunch
az sig image-version create -g <rg> --gallery-name <gallery> --gallery-image-definition <app> \
  --gallery-image-version <approved-semver> --virtual-machine <build-vm-id> \
  --target-regions <region1> <region2>=2 --replica-count 1
```

Prefer Packer (`infra-packer-azureImage-build`) or Azure Image Builder pipelines over hand-built images.

## Availability (zones, VMSS)

Zones > availability sets for new deployments. VMSS Flexible orchestration is the default:

```bash
az vmss create -g <rg> -n <app>-vmss --orchestration-mode Flexible \
  --image <gallery-image-version-id> --vm-sku Standard_D4s_v5 --instance-count 2 --zones 1 2 3 \
  --vnet-name <vnet> --subnet <app-subnet> --lb "" --admin-username <admin-user> --ssh-key-values @<public-key-file> \
  --upgrade-policy-mode Rolling --custom-data cloud-init.yaml
az monitor autoscale create -g <rg> --resource <app>-vmss --resource-type Microsoft.Compute/virtualMachineScaleSets \
  --name <app>-autoscale --min-count 2 --max-count 10 --count 2
az monitor autoscale rule create -g <rg> --autoscale-name <app>-autoscale --condition "Percentage CPU > 70 avg 5m" --scale out 2
az monitor autoscale rule create -g <rg> --autoscale-name <app>-autoscale --condition "Percentage CPU < 30 avg 10m" --scale in 1
```

Add the Application Health extension so rolling upgrades and automatic repairs use application health. Drain stateful work before scale-in; use Spot only for stateless workloads that tolerate eviction.

## Day-2 operations

```bash
az vm list -g <rg> -d -o table
az vm get-instance-view -g <rg> -n <vm> --query instanceView.statuses -o table
az vm deallocate -g <rg> -n <vm>     # stop billing compute ('stop' alone keeps billing)
az vm resize -g <rg> -n <vm> --size Standard_D8s_v5
az vm run-command invoke -g <rg> -n <vm> --command-id RunShellScript --scripts "systemctl --failed; df -h"
az vm boot-diagnostics enable -g <rg> -n <vm>     # managed storage
az vm boot-diagnostics get-boot-log -g <rg> -n <vm>
az backup protection enable-for-vm -g <rg> --vault-name <vault> --vm <vm> --policy-name <policy>
# DESTRUCTIVE: az vm delete -g <rg> -n <vm>   (omit --yes; check attached disks/NICs with --force-deletion none)
```

Patching: Azure Update Manager (`az maintenance` / periodic assessment) for RHEL/Debian.

## Terraform/OpenTofu

Prefer Azure Verified Modules (`Azure/avm-res-compute-virtualmachine/azurerm`, pin version — see `infra-terraform-avmModule-develop`). Raw resource:

```hcl
resource "azurerm_linux_virtual_machine" "app" {
  name                  = "${var.env}-app"
  resource_group_name   = azurerm_resource_group.main.name
  location              = azurerm_resource_group.main.location
  size                  = "Standard_D4s_v5"
  zone                  = "1"
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.app.id]
  secure_boot_enabled   = true
  vtpm_enabled          = true
  encryption_at_host_enabled = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "9-lvm-gen2"
    version   = var.approved_image_version
  }
  identity { type = "SystemAssigned" }
  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))
}
```

Provider baseline: `hashicorp/azurerm` `5.11.0` (checked 2026-10-28); pin it in the IaC configuration and lock file.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `SkuNotAvailable` / allocation failed | other zone/size (`list-skus`), quota (`list-usage`) |
| SSH refused | NSG/ASG, Bastion subnet rules, Entra SSH role (`Virtual Machine Administrator Login`) |
| No outbound internet | NAT Gateway on subnet (default outbound retired) |
| Image VM won't boot | not generalized / Gen1-vs-Gen2 / TrustedLaunch mismatch; boot diagnostics |
| VMSS upgrade stuck | health extension/probe failing; `az vmss rolling-upgrade get-latest` |
| Slow disk | disk tier/IOPS cap vs VM cap (`az vm show --query hardwareProfile`); Premium SSD v2 |
| Network latency | validate SKU networking limits, NIC acceleration, zone placement, and the actual path |
