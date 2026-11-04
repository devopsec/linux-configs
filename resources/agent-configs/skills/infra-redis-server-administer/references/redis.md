# Redis / Valkey

## Contents

1. Versions & licensing
2. Secure config
3. CLI without leaking secrets
4. Persistence
5. Sentinel (HA)
6. Cluster
7. Patterns
8. Monitoring
9. Containers (dev)
10. Troubleshooting

## 1. Versions & licensing

- Reference pins checked 2026-10-28 against [Redis releases](https://github.com/redis/redis/releases) and [Valkey releases](https://github.com/valkey-io/valkey/releases): Redis Open Source **8.10.3** and Valkey **9.1.3**. Redis 8 is tri-licensed under RSALv2/SSPLv1/AGPLv3; Valkey is BSD-licensed.
- **Valkey** (BSD, Linux Foundation fork; RHEL 10/Fedora/Debian ship it as `valkey`) is wire-compatible; commands below work with `valkey-cli`.
- GCP managed: Memorystore for Redis/Valkey → `infra-gcp-any-manage`.

```bash
sudo dnf install -y valkey   # or redis on older RHEL; systemctl enable --now valkey
sudo apt install -y redis-server
```

## 2. Secure config (`/etc/redis/redis.conf` / `/etc/valkey/valkey.conf`)

```ini
bind 127.0.0.1 <private-ip>
protected-mode yes
port 6379
# TLS (optional, recommended across hosts)
# tls-port 6380 / tls-cert-file / tls-key-file / tls-ca-cert-file
aclfile /etc/redis/users.acl
maxmemory 2gb
maxmemory-policy allkeys-lru      # cache; use noeviction for queues/locks/source-of-truth data
timeout 300
tcp-keepalive 60
rename-command DEBUG ""
```

ACL file (passwords stored as SHA-256 hashes; generate from env, never literals in repo):

```bash
hash=$(printf '%s' "$REDIS_APP_PASSWORD" | sha256sum | cut -d' ' -f1)
echo "user app on #${hash} ~app:* &app:* +@all -@dangerous" | sudo tee -a /etc/redis/users.acl >/dev/null
echo "user default off" | sudo tee -a /etc/redis/users.acl >/dev/null
redis-cli ACL LOAD
```

Prefer ACL `-@dangerous` (blocks `FLUSHALL`, `CONFIG`, `KEYS`, `DEBUG`…) over `rename-command` (breaks tooling, deprecated in spirit).

## 3. CLI without leaking secrets

```bash
export REDISCLI_AUTH="$(gcloud secrets versions access latest --secret=<redis-secret>)"
redis-cli --user app -h <host> PING
```

Never `redis-cli -a <password>` (visible in `ps`/history).

## 4. Persistence

| Use | Config |
|---|---|
| Pure cache | `save ""`, `appendonly no` |
| Durable (≤1s loss) | `appendonly yes`, `appendfsync everysec` + RDB `save 3600 1 300 100 60 10000` |
| Fast restarts | `aof-use-rdb-preamble yes` (default) |

Redis 7+ uses multi-part AOF in `appenddirname`. Fork for RDB/AOF rewrite needs memory headroom — set `vm.overcommit_memory = 1` and disable THP (`/sys/kernel/mm/transparent_hugepage/enabled = never`).

## 5. Sentinel (HA)

```ini
# sentinel.conf — ≥3 sentinels on separate hosts
port 26379
sentinel monitor mymaster <primary-ip> 6379 2
sentinel auth-user mymaster sentinel_user
sentinel auth-pass mymaster <from-secret-manager>   # templated at deploy time, file mode 0600
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 60000
sentinel parallel-syncs mymaster 1
```

```bash
redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster
redis-cli -p 26379 SENTINEL replicas mymaster
```

Clients must be Sentinel-aware (discover primary), not hardcode its IP.

## 6. Cluster

```bash
redis-cli --cluster create <n1>:6379 <n2>:6379 <n3>:6379 <n4>:6379 <n5>:6379 <n6>:6379 --cluster-replicas 1
redis-cli -c -h <node> CLUSTER INFO
redis-cli --cluster check <node>:6379
redis-cli --cluster rebalance <node>:6379
```

`cluster-enabled yes`, `cluster-config-file nodes.conf`, `cluster-node-timeout 5000`. Multi-key ops need hash tags: `{user:42}:profile`, `{user:42}:cart`. Bus port = data port + 10000 must be open between nodes.

## 7. Patterns

- Cache-aside with TTL (`SET k v EX 300`); add jitter to TTLs to avoid stampedes.
- Lock: `SET lock:<res> <token> NX PX 30000`; release with compare-and-delete Lua (`if redis.call('get',KEYS[1])==ARGV[1] then return redis.call('del',KEYS[1]) end return 0`). Single-instance locks are advisory — use DB constraints for correctness.
- Rate limiting: fixed window `INCR` + `EXPIRE NX`; Redis 8.8+ has `INCREX` window counters.
- Queues: prefer Streams (`XADD`/`XREADGROUP`/`XACK`) over lists for at-least-once delivery; on GCP consider Pub/Sub instead.
- Never `KEYS *` in prod — `SCAN 0 MATCH <pattern> COUNT 1000`.

## 8. Monitoring

```bash
redis-cli INFO memory | grep -E 'used_memory_human|maxmemory_human|mem_fragmentation_ratio'
redis-cli INFO stats  | grep -E 'keyspace_(hits|misses)|evicted_keys|rejected_connections'
redis-cli INFO replication
redis-cli SLOWLOG GET 10
redis-cli --latency-history -i 5
redis-cli --bigkeys          # sampling scan; run off-peak
```

`MONITOR` is debug-only (heavy, exposes data). Exporter: `oliver006/redis_exporter`. Alert: memory > 90% maxmemory, evictions on non-cache instances, replication link down, rejected connections.

## 9. Containers (dev)

```yaml
services:
  redis:
    image: redis:8.10.3-alpine
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    ports: ["127.0.0.1:6379:6379"]
    volumes: ["./redis.conf:/usr/local/etc/redis/redis.conf:ro", "redis_data:/data"]
    healthcheck:
      test: ["CMD-SHELL", "REDISCLI_AUTH=$$REDIS_PASSWORD redis-cli ping"]
    environment:
      REDIS_PASSWORD: ${REDIS_PASSWORD:?set in .env}
volumes: { redis_data: {} }
```

Dropped upstream's redis-commander sidecar (embedded password, extra exposed UI).

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `OOM command not allowed` | `maxmemory` reached with `noeviction` | raise memory or eviction policy (if cache) |
| latency spikes every N min | fork for RDB/AOF rewrite, THP | overcommit + THP off, schedule rewrites |
| `CROSSSLOT` | multi-key across slots | hash tags |
| Sentinel doesn't fail over | no quorum / auth mismatch | ≥3 sentinels, check `auth-user`/`auth-pass` |
| `NOAUTH` / `WRONGPASS` | ACL/user mismatch | `ACL WHOAMI`, `ACL LIST` (as admin) |
