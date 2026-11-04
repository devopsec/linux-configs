# MongoDB

## Contents

1. Versions & install
2. Auth, users, network
3. Replica set
4. Indexing & query diagnostics
5. Monitoring
6. Tuning
7. Backups (pointer)
8. Containers (dev)
9. Troubleshooting

## 1. Versions & install

- Reference pins checked 2026-10-28 against MongoDB's [9.0](https://www.mongodb.com/docs/manual/release-notes/9.0/) and [8.0](https://www.mongodb.com/docs/manual/release-notes/8.0/) release notes: **9.0.4** and **8.0.34**. Prefer the supported major compatible with the application; 9.0 is not an LTS designation. MongoDB Server is SSPL-licensed; confirm license fit before adopting.
- Install from the official signed repo for your distro/major (RHEL: `/etc/yum.repos.d/mongodb-org-<ver>.repo` with `gpgkey=`; Debian/Ubuntu: keyring in `/usr/share/keyrings` + `signed-by=`). Match the repo codename to the host release (upstream hardcoded `jammy`/7.0).
- Upgrades go one major at a time and require `setFeatureCompatibilityVersion` steps: `db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })`.

## 2. Auth, users, network

```yaml
# /etc/mongod.conf
net:
  port: 27017
  bindIp: 127.0.0.1,<private-ip>      # never 0.0.0.0 on public NICs
  tls:
    mode: requireTLS
    certificateKeyFile: /etc/mongod/tls/server.pem
    CAFile: /etc/mongod/tls/ca.pem
security:
  authorization: enabled
  keyFile: /etc/mongod/keyfile         # or x.509 member auth
```

```javascript
// mongosh: passwordPrompt() avoids literals in history/files
use admin
db.createUser({ user: "dbadmin", pwd: passwordPrompt(),
  roles: [ { role: "userAdminAnyDatabase", db: "admin" }, { role: "clusterMonitor", db: "admin" } ] })
use app
db.createUser({ user: "app_rw", pwd: passwordPrompt(), roles: [ { role: "readWrite", db: "app" } ] })
```

Connect with credentials from env: `mongosh "$MONGODB_URI"` where the URI is fetched from Secret Manager; never paste it into chat. Keyfile: `openssl rand -base64 756 > keyfile; chmod 400; chown mongod:mongod` (user is `mongod` on RHEL, `mongodb` on Debian).

## 3. Replica set

Three data-bearing members (avoid arbiters in new deployments — they hurt majority write availability).

```javascript
rs.initiate({ _id: "rs0", members: [
  { _id: 0, host: "<mongo-1-private-host>:27017", priority: 2 },
  { _id: 1, host: "<mongo-2-private-host>:27017" },
  { _id: 2, host: "<mongo-3-private-host>:27017" } ] })
rs.status()
rs.printSecondaryReplicationInfo()   // lag per member
rs.printReplicationInfo()            // oplog window — keep ≥ 24–72h
```

Planned failover: `rs.stepDown(60)`. Resize oplog online: `db.adminCommand({ replSetResizeOplog: 1, size: <MB> })`.

## 4. Indexing & query diagnostics

```javascript
db.orders.createIndex({ userId: 1, createdAt: -1 })          // ESR rule: Equality, Sort, Range
db.sessions.createIndex({ createdAt: 1 }, { expireAfterSeconds: 2592000 })   // TTL
db.orders.find({ userId: 42 }).sort({ createdAt: -1 }).explain("executionStats")
// look for COLLSCAN, totalDocsExamined >> nReturned
db.orders.aggregate([{ $indexStats: {} }])                    // unused indexes
db.orders.hideIndex("<name>")  // test removal safely before dropIndex
```

## 5. Monitoring

```javascript
db.serverStatus().connections
db.serverStatus().opcounters
db.serverStatus().wiredTiger.cache["bytes currently in the cache"]
db.currentOp({ active: true, secs_running: { $gte: 5 } })
db.setProfilingLevel(1, { slowms: 100 })   // WRITE: profiler adds overhead; revert with level 0
db.system.profile.find().sort({ ts: -1 }).limit(5)
```

Kill an op (**confirm first**): `db.killOp(<opid>)`. Exporter: `percona/mongodb_exporter` with a `clusterMonitor` user.

## 6. Tuning

- WiredTiger cache default = 50% of (RAM − 1GB); lower `storage.wiredTiger.engineConfig.cacheSizeGB` only on shared hosts/containers.
- `ulimit -n` ≥ 64000 and `nproc` ≥ 64000 (systemd `LimitNOFILE=`), XFS for data.
- Transparent Huge Pages: ≤7.0 → disable; 8.0+ (new TCMalloc) → enable (`always`/`madvise` per docs). Verify against the version-specific production notes.
- Write concern `w: "majority"` (default since 5.0) for durability.
- `storage.journal.enabled` was removed in 6.1+ — delete it from old configs or mongod won't start.

## 7. Backups

`mongodump --uri "$MONGODB_URI" --oplog --gzip --archive=<file>` (replica set, point-in-time consistent), restore with `mongorestore --oplogReplay` (`--drop` is **destructive** — confirm). For large data use filesystem/disk snapshots with `db.fsyncLock()` or Ops Manager/Atlas. Retention/drills → `infra-any-backupRecovery-manage`.

## 8. Containers (dev)

```yaml
services:
  mongo:
    image: mongo:9.0.4
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_ROOT_USER:-root}
      MONGO_INITDB_ROOT_PASSWORD_FILE: /run/secrets/mongo_root
    secrets: [mongo_root]
    ports: ["127.0.0.1:27017:27017"]
    volumes: ["mongo_data:/data/db"]
secrets:
  mongo_root: { file: ./secrets/mongo_root.txt }
volumes: { mongo_data: {} }
```

## 9. Troubleshooting

For schema validation on a large collection, build a validator with `validationAction: "warn"` first, assess existing documents and application compatibility, then switch to `"error"` in a separately approved change. Index builds still consume I/O; schedule large builds away from peak traffic.

| Symptom | Cause | Fix |
|---|---|---|
| `COLLSCAN` in explain | missing/wrong-order index | ESR compound index |
| member stuck `RECOVERING` / too stale | fell off oplog window | grow oplog; initial sync the member (**wipes its data**) |
| `too many open files` | low fd limit | systemd `LimitNOFILE=64000` |
| auth fails for admin | wrong `authSource` | add `authSource=admin` to URI |
| mongod won't start after upgrade | removed options (`journal.enabled`) / FCV mismatch | clean config; step FCV |
