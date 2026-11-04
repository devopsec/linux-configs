# Compute Engine operations

All project, zone, region, subnet, instance, and service-account identifiers are runtime inputs. Use `gcloud config list` only to inspect; explicitly pass the intended project for changes.

## Secure VM baseline

- Prefer RHEL 9-family or Debian 12-family images where they match the workload policy; use an image family for routine patching or an exact image for reproducible production builds.
- Use Shielded VM, OS Login, a dedicated service account, minimum IAM roles, and no external IP unless the VM must serve public traffic.
- Use IAP TCP forwarding for administration; allow its published source range only on the administrative port and to the intended target identity/tag.
- Keep the guest firewall and VPC firewall policy consistent. Do not place credentials in startup metadata or user data.

```bash
gcloud compute instances create "$VM_NAME" \
  --project="$PROJECT_ID" --zone="$ZONE" --machine-type="$MACHINE_TYPE" \
  --image-family="$IMAGE_FAMILY" --image-project="$IMAGE_PROJECT" \
  --subnet="$SUBNET" --no-address \
  --service-account="$RUNTIME_SERVICE_ACCOUNT" --scopes=cloud-platform \
  --metadata=enable-oslogin=TRUE \
  --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring
```

Use a dedicated SA with only the roles the workload needs; the `cloud-platform` OAuth scope does not grant IAM permissions by itself. Reserve a static external IP only when a public endpoint requires stable addressing.

## Startup scripts

Keep startup scripts idempotent and review them as code. Prefer a pinned, checksum-verified artifact and a project-owned installer. Fetch secret values at runtime from Secret Manager, never from instance metadata. On RHEL-family guests keep SELinux enforcing and use systemd units for long-running services.

On Debian-family guests use the platform package/service tooling. In either case, host firewall policy complements (and does not replace) VPC firewall policy. Keep service units and boot configuration version-controlled with their owning platform.

## Templates and managed instance groups

Use immutable, versioned instance templates for stateless services. Roll out with a managed instance group update policy, health checks, and a reasonable initial delay. Autoscaling on CPU is unsuitable for workloads whose state or sessions cannot drain safely.

```bash
gcloud compute instance-templates create "$TEMPLATE" \
  --project="$PROJECT_ID" --region="$REGION" \
  --machine-type="$MACHINE_TYPE" --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" --subnet="$SUBNET" --no-address \
  --service-account="$RUNTIME_SERVICE_ACCOUNT" --scopes=cloud-platform \
  --metadata=enable-oslogin=TRUE --shielded-secure-boot --shielded-vtpm

gcloud compute instance-groups managed rolling-action start-update "$MIG" \
  --project="$PROJECT_ID" --region="$REGION" \
  --version="template=$TEMPLATE" --max-surge=1 --max-unavailable=0
```

Permit Google health-check probe ranges only to the ports and target backends they probe. Review regional capacity and quotas before choosing machine families or MIG size.

Use Spot VMs only for interruptible batch/load-test work, never for stateful or protocol-sensitive public endpoints. For stateful MIGs, declare disks and internal addresses explicitly and verify that recreation preserves the required identity.

## Storage, snapshots, and operations

- Decide whether attached data disks must survive VM deletion; verify `autoDelete` before replacing or deleting instances.
- Configure a retention schedule and test restores into a new disk/instance before relying on it for recovery.
- Check current operation status and boot serial output before retrying failed creates.
- Stop a VM before creating a golden image when application consistency requires it; account for the outage window.

```bash
gcloud compute instances describe "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE"
gcloud compute instances get-serial-port-output "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE"
gcloud compute ssh "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --tunnel-through-iap
```

**Destructive:** instance deletion, disk deletion, and snapshot restoration can cause irreversible loss or replace target data. Confirm the exact resource and recoverability before acting.

## Troubleshooting

| Symptom | Check |
|---|---|
| VM stuck in `STAGING` | Quota, zone capacity, IAM, and recent operations. |
| Startup script failed | Serial-port output and guest startup-script service logs. |
| IAP SSH denied | IAP source rule, tunnel role, OS Login role, and target selection. |
| MIG continually replaces VMs | Health-check path/port, probe firewall, and initial delay. |
| Private VM cannot reach APIs | Private Google Access, DNS, route, and service enablement. |

## References

- [Compute Engine documentation](https://cloud.google.com/compute/docs) — checked 2026-10-28.