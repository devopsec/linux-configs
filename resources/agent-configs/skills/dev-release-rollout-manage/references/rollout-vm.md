# Rollout & rollback on VMs (SIP/RTP nodes)

## Contents
- Strategy choice
- Artifact deploy on a node (in-place, symlink switch)
- Draining a SIP node
- Canary on Compute Engine MIGs
- Blue-green for SIP edges
- Rollback
- Checklists

## Strategy choice

| Strategy | Fits | SIP caveat |
|---|---|---|
| In-place rolling (node by node) | fixed-IP nodes whitelisted by carriers | drain each node first; one at a time |
| MIG canary (`--canary-version`) | stateless proxies behind passthrough LB | new instances get new IPs unless stateful MIG / reserved IPs |
| Blue-green (two pools) | big changes, fast flip-back | carriers must accept both IP sets, or flip DNS/SRV, or move reserved IPs |
| Image bake (boot image per release) | immutable infra | rollback = previous image/template |

Carrier/peer IP allowlists and SIP registrations make "replace the VM" heavier than on HTTP — prefer in-place artifact swap or stateful MIGs with preserved IPs for edge proxies.

## Artifact deploy on a node (in-place, symlink switch)

```bash
# variables from the release manifest — never typed by hand
VER="vX.Y.Z"; BUILD="git-<SHORT_SHA>"; DIGEST="<sha256>"
gcloud artifacts generic download --location="$REGION" --repository="$REPO" \
  --package="$PKG" --version="$BUILD" --destination="/var/tmp/$BUILD"
echo "$DIGEST  /var/tmp/$BUILD/$PKG-$BUILD.tar.gz" | sha256sum -c -        # refuse on mismatch
install -d "/opt/$PKG/releases/$VER"
tar -xzf "/var/tmp/$BUILD/$PKG-$BUILD.tar.gz" -C "/opt/$PKG/releases/$VER"
"/opt/$PKG/releases/$VER/install.sh" --check                 # if the installer supports a dry-run/check mode
ln -sfn "/opt/$PKG/releases/$VER" "/opt/$PKG/current.new" && mv -T "/opt/$PKG/current.new" "/opt/$PKG/current"   # atomic switch
systemctl restart <service>.service                          # after drain (below)
```

Keep the previous `releases/<ver>` directory (at least N-1) — rollback is a symlink flip. Config/certs come from Secret Manager at boot, never from the artifact. Validate Kamailio config before restart: `kamailio -c -f /etc/kamailio/kamailio.cfg`.

## Draining a SIP node

1. **Stop new traffic**
   - Use the service's approved proxy/LB control to stop new traffic; resolve node IDs, peer endpoints, and health-check behavior from deployment configuration.
   - For DNS-based routing, change only the approved record weight and respect its TTL.
   - For a cloud load balancer, remove or mark the backend unhealthy and configure the approved connection-drain timeout.
2. **Wait for sessions to end** — use the service's supported dialog/session counters or the approved maximum drain window; obtain the duration and maximum session age from the operator.
3. **Deploy + restart**, then run the approved SIP OPTIONS/health probe and verify registration/session counts.
4. **Re-enable** using the service's approved traffic-control command; watch agreed signaling and media indicators for the bake time.

Never restart a media relay with active sessions unless dropped media is explicitly accepted. Encrypted-transport and WebSocket clients reconnect; expect registration bursts and stagger nodes.

## Canary on Compute Engine MIGs

```bash
# canary: 1 instance on the new template, rest stay old
gcloud compute instance-groups managed rolling-action start-update "$MIG" --region="$REGION" \
  --version=template="$TEMPLATE_OLD" \
  --canary-version=template="$TEMPLATE_NEW",target-size=1 \
  --max-surge=1 --max-unavailable=0 --replacement-method=substitute
gcloud compute instance-groups managed describe "$MIG" --region="$REGION" --format='yaml(status)'
gcloud compute instance-groups managed list-instances "$MIG" --region="$REGION"

# widen after bake time (e.g. 25% → 100%)
gcloud compute instance-groups managed rolling-action start-update "$MIG" --region="$REGION" \
  --version=template="$TEMPLATE_OLD" --canary-version=template="$TEMPLATE_NEW",target-size=25%
gcloud compute instance-groups managed rolling-action start-update "$MIG" --region="$REGION" \
  --version=template="$TEMPLATE_NEW" --max-surge=1 --max-unavailable=0
```

- Autohealing health check should be a real SIP/HTTP probe (e.g. sidecar HTTP endpoint checking `kamcmd`), with `initial-delay` covering boot + install.
- Stateful MIG (`--stateful-internal-ip`/`--stateful-external-ip`) preserves IPs across recreation — needed for allowlisted SIP edges.
- MIG replacement does **not** drain SIP dialogs by itself; combine with dispatcher/SRV drain or a shutdown script that drains (shutdown scripts have a limited time budget — verify current limit).
- Manage templates/MIGs in OpenTofu; the rollout commands above are the operational step.

## Blue-green for SIP edges

1. Build **green** pool (new template/image) alongside **blue**; apply the approved signaling, media, and health-check firewall policy from deployment configuration.
2. Smoke-test green on its own IPs (test trunk / internal numbers, `sipp` scenarios).
3. Shift: dispatcher weights (`ds` attrs `weight=`) or SRV weights blue 90/green 10 → 50/50 → 0/100; or move reserved static IPs to green (instant, but drops in-flight dialogs on blue — drain first).
4. Keep blue running (drained) for the rollback window, then retire.

## Rollback

| Deploy style | Rollback |
|---|---|
| Symlink releases | drain → `ln -sfn /opt/$PKG/releases/<prev> …` + `mv -T` → restart → re-enable |
| MIG | `rolling-action start-update "$MIG" --version=template="$TEMPLATE_OLD" --max-unavailable=0` |
| Blue-green | shift weights / IPs back to blue |
| Image bake | point template back to previous image |

Rollback is a deployment too: same drain discipline, same health checks. Do not roll back DB schema blindly — migrations must be backward-compatible (expand/contract).

## Checklists

Before: release verified · manifest PR merged · rollback target identified and still downloadable · thresholds agreed · change window + on-call · peers notified if IPs/certs change.
During: one node/canary first · watch SIP KPIs + Cloud Logging errors for bake time · stop at first threshold breach.
After: all nodes on version (`ls -l /opt/$PKG/current` / MIG status) · manifest/runbook updated · post-release note.
