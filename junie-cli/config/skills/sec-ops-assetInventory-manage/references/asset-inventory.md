# Security asset inventory reference

## Inventory domains

| Domain | Candidate sources | Useful fields |
|---|---|---|
| Cloud and network | Organization/project/resource exports, networks, routes, firewalls, load balancers, DNS, VPN | Stable ID/type, owner, region, environment, status, exposure, dependencies, discovery time |
| Compute and software | VM/image/container inventories, package managers, service managers, endpoint tools, repositories | Host/image, OS/package version, service owner, lifecycle, patch source, runtime purpose |
| Data and storage | Database catalogs, schemas/roles, object stores, queues, backups, logs | Data owner/classification, location, access, encryption, retention, producers/consumers |
| Identity and security | Identity provider, role bindings, service identities/key metadata, key/certificate catalogs, logging/monitoring | Identity/resource link, owner, privilege, purpose, expiry/review date; never credential contents |
| Delivery and dependencies | Repositories, build/deploy systems, artifact stores, vendors/subprocessors | Pipeline owner, environment, approvals, artifact identity, target, vendor/service/data access |
| Data flows | Approved diagrams, application config, interface catalogs, network flow telemetry | Direction, protocol, trust boundary, data fields/classification, owner, retention, protection per leg |

## Reconciliation

Record stable identifier/name, type, owner, environment, location, status, classification, compliance scope, dependencies, source, and last-seen date as available. Reconcile machine discovery with application/host/database records, identity grants, build/deployment targets, vendor lists, data-flow diagrams, and operational ownership.

Assign an owner and discovery method for missing, unsupported, ephemeral, or manually managed assets. Document exclusions and source blind spots. Preserve dated exports and query parameters; review changes and orphaned resources. Retirement evidence should include access removal, data disposition, and inventory status update.

Labels and tags are metadata, not access controls; do not put credentials or personal data in them. Do not claim full coverage from one cloud inventory export.