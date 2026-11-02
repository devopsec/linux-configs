# PostgreSQL administration

## Contents

1. Versions & install
2. Connecting without leaking secrets
3. Tuning (`postgresql.conf`)
4. Authentication (`pg_hba.conf`)
5. Roles & least-privilege grants
6. Streaming replication
7. Logical replication
8. PgBouncer
9. Containers (dev only)
10. Troubleshooting

## 1. Versions & install

- Reference pin: **PostgreSQL 18.6**, checked 2026-10-28 against the [official 18.6 release notes](https://www.postgresql.org/docs/release/18.6/). PostgreSQL 19 is still a release candidate; do not use it in production. Check the deployed version with `SELECT version();` and follow the vendor's supported upgrade path.
- `pg_dump`/`psql` client may be newer than the server (dumping 15 with a 16+ client is fine); restore into **same or newer** major.
- Major upgrades: `pg_upgrade --check` first (dry run), or dump/restore, or logical replication for near-zero downtime. Cloud SQL: in-place major upgrade via `gcloud sql instances patch --database-version` → `infra-gcp-cloudSql-manage`.

```bash
# RHEL-family: configure the signed PGDG repo for this OS release; select the exact 18.6 package NEVRA
# from signed repository metadata (package NEVRAs differ by distro build).
sudo dnf list --showduplicates postgresql18-server postgresql18-contrib
sudo dnf -qy module disable postgresql
sudo dnf install -y 'postgresql18-server-<exact-18.6-nevra>' 'postgresql18-contrib-<exact-18.6-nevra>'
sudo /usr/pgsql-18/bin/postgresql-18-setup initdb
sudo systemctl enable --now postgresql-18
# Debian: query the signed distro/PGDG repo, then install exact matching 18.6 package versions
sudo apt-cache madison postgresql-18 postgresql-contrib-18
sudo apt install -y 'postgresql-18=<exact-18.6-deb-version>' 'postgresql-contrib-18=<exact-18.6-deb-version>'
```

Paths differ: RHEL `/var/lib/pgsql/18/data/`, Debian `/etc/postgresql/<ver>/main/` + `/var/lib/postgresql/<ver>/main/`. Ask the server: `SHOW config_file; SHOW hba_file; SHOW data_directory;`.

SELinux (RHEL): non-default data dir needs `semanage fcontext -a -t postgresql_db_t '<dir>(/.*)?' && restorecon -Rv <dir>`; non-default port needs `semanage port -a -t postgresql_port_t -p tcp <port>`. firewalld: `firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=<app-cidr> port port=5432 protocol=tcp accept'`.

## 2. Connecting without leaking secrets

```bash
export PGHOST=<host> PGPORT=5432 PGDATABASE=<db> PGUSER=<role>
export PGPASSWORD="$(gcloud secrets versions access latest --secret=<pg-secret-name>)"
export PGSSLMODE=verify-full PGSSLROOTCERT=<path-to-server-ca.pem>
psql -X -v ON_ERROR_STOP=1 -c 'select current_user, inet_server_addr();'
unset PGPASSWORD
```

Alternatives: a `PGPASSFILE` with mode 0600 outside the repo; Cloud SQL Auth Proxy / IAM DB auth (no static password). Local admin on VM: `sudo -u postgres psql` (peer auth).

## 3. Tuning (`postgresql.conf`)

Prefer `ALTER SYSTEM SET …;` (writes `postgresql.auto.conf`) or a drop-in under `conf.d/` with `include_dir`. Check `SELECT name, setting, unit, context, pending_restart FROM pg_settings WHERE name = '<param>';`.

| Param | Starting point | Notes |
|---|---|---|
| `listen_addresses` | private IP(s), not `*` | restart |
| `max_connections` | 100–300 | restart; put PgBouncer in front instead of raising high |
| `shared_buffers` | ~25% RAM | restart |
| `effective_cache_size` | 50–75% RAM | planner hint only |
| `work_mem` | 8–64MB | per sort/hash node *per query*; watch `max_connections × work_mem` |
| `maintenance_work_mem` | 256MB–2GB | VACUUM, CREATE INDEX |
| `checkpoint_completion_target` | 0.9 (default) | |
| `max_wal_size` / `min_wal_size` | 4GB / 1GB | fewer forced checkpoints (`log_checkpoints`) |
| `random_page_cost` | 1.1 on SSD/PD-SSD | |
| `effective_io_concurrency` | 200 on SSD | PG18 also has `io_method` (async I/O; default `worker`) |
| `shared_preload_libraries` | `pg_stat_statements` (+ `pg_cron` if used) | restart |
| `log_min_duration_statement` | 250–1000ms | slow query log |
| `log_lock_waits`, `log_checkpoints`, `log_autovacuum_min_duration=10s` | on | |
| `idle_in_transaction_session_timeout` | 5–15min | kills forgotten transactions holding locks/xmin |

Reload: `SELECT pg_reload_conf();`. Restart only if `pending_restart = true`.

## 4. Authentication (`pg_hba.conf`)

First match wins; finish with explicit reject. `password_encryption = scram-sha-256` (default since 14; `md5` is deprecated in 18).

```
# TYPE    DATABASE     USER          ADDRESS          METHOD
local     all          postgres                       peer
hostssl   <db>         <app_role>    <app-subnet-cidr> scram-sha-256
hostssl   <db>         +readonly     <app-subnet-cidr> scram-sha-256
hostssl   replication  replicator    <replica-ip>/32  scram-sha-256
host      all          all           0.0.0.0/0        reject
host      all          all           ::/0             reject
```

Check before reload: `SELECT * FROM pg_hba_file_rules WHERE error IS NOT NULL;` then `SELECT pg_reload_conf();`.

## 5. Roles & least-privilege grants

Pattern: owner role (NOLOGIN, owns schema/objects, used by migrations) ← app role (DML) ← readonly group role.

```sql
-- passwords set interactively (\password <role>) or from env via psql variables, never inline literals
CREATE ROLE app_owner NOLOGIN;
CREATE ROLE app_rw LOGIN;
CREATE ROLE readonly NOLOGIN;
CREATE ROLE analyst LOGIN IN ROLE readonly;

REVOKE ALL ON DATABASE <db> FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;       -- default since PG15
GRANT CONNECT ON DATABASE <db> TO app_rw, readonly;
GRANT USAGE ON SCHEMA public TO app_rw, readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly;
-- future objects created by the owner
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT SELECT ON TABLES TO readonly;
```

Set a password from an env var without echoing it:

```bash
psql -X -v pw="$NEW_ROLE_PASSWORD" -c "ALTER ROLE app_rw PASSWORD :'pw';"
```

Audit: `\du+`, `\dp <table>`, `\ddp` (default privileges), `SELECT * FROM information_schema.role_table_grants WHERE grantee = '<role>';`.
Built-in roles: `pg_read_all_data`, `pg_write_all_data`, `pg_monitor` (for exporters), `pg_signal_backend`.

## 6. Streaming replication

Primary:

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN;   -- then \password replicator
SELECT pg_create_physical_replication_slot('replica1');
```

`postgresql.conf`: `wal_level = replica`, `max_wal_senders = 10`, `max_replication_slots = 10`, `max_slot_wal_keep_size = 50GB` (cap WAL retained for a dead slot), `hot_standby = on`. Add the `hostssl replication` line to `pg_hba.conf`.

Replica (**DESTRUCTIVE: wipes the replica data dir — confirm host first**):

```bash
sudo systemctl stop postgresql-18
# verify you are on the REPLICA: hostname; ls <data_dir>
sudo -u postgres rm -rf <data_dir>/*
sudo -u postgres env PGPASSWORD="$REPL_PASSWORD" pg_basebackup -h <primary-ip> -U replicator \
  -D <data_dir> -X stream -S replica1 -R --checkpoint=fast --progress
sudo systemctl start postgresql-18
```

`-R` writes `standby.signal` + `primary_conninfo` into `postgresql.auto.conf`; keep the password out of that file by using a `PGPASSFILE` (0600) for the postgres user instead.

Verify:

```sql
-- primary
SELECT application_name, client_addr, state, sync_state,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_lag_bytes,
       replay_lag
FROM pg_stat_replication;
SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots;
-- replica
SELECT pg_is_in_recovery(), now() - pg_last_xact_replay_timestamp() AS replay_delay;
```

Promote: `SELECT pg_promote();` (fence the old primary first). Inactive slots with growing `retained` = disk-full risk; drop with `SELECT pg_drop_replication_slot('<name>');` after confirming the consumer is gone.

## 7. Logical replication

For major-version upgrades, partial replication or feeding analytics: `wal_level = logical`; publisher `CREATE PUBLICATION p FOR TABLE …;`; subscriber (schema pre-created via `pg_dump --schema-only`) `CREATE SUBSCRIPTION s CONNECTION '…' PUBLICATION p;`. Sequences are not replicated before PG19 — resync `setval` at cutover. DDL is not replicated.

## 8. PgBouncer

Transaction pooling for many short app connections. Gotchas in `transaction` mode: no session state (`SET`, advisory locks, `LISTEN`); prepared statements need PgBouncer ≥1.21 with `max_prepared_statements`. Use `auth_type = scram-sha-256` + `auth_query` against a dedicated lookup role instead of plain-text `userlist.txt`. Size: `default_pool_size` ≈ server cores × 2–4.

## 9. Containers (dev only)

```yaml
# compose.yaml — no top-level "version:" key (obsolete in Compose v2)
services:
  postgres:
    image: postgres:18
    environment:
      POSTGRES_USER: ${PG_USER:-app}
      POSTGRES_PASSWORD_FILE: /run/secrets/pg_password
      POSTGRES_DB: ${PG_DB:-app}
    secrets: [pg_password]
    ports: ["127.0.0.1:5432:5432"]
    volumes: ["pg_data:/var/lib/postgresql"]   # PG18 image: mount the parent dir
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
secrets:
  pg_password:
    file: ./secrets/pg_password.txt   # gitignored
volumes:
  pg_data:
```

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `too many connections` / `remaining connection slots are reserved` | leaks, no pooling | find idle sessions (monitoring ref), add PgBouncer, set `idle_session_timeout` |
| `password authentication failed` | wrong secret or hba line order | `pg_hba_file_rules`, server log shows matched line |
| `no pg_hba.conf entry` | missing/ordered-after-reject line or no SSL | add `hostssl` line, reload |
| replica lag growing | replica I/O, long queries on replica, network | `pg_stat_replication`, `hot_standby_feedback`, `max_standby_streaming_delay` |
| disk filling with WAL | inactive slot, failing `archive_command` | `pg_replication_slots`, `pg_stat_archiver.failed_count` |
| `could not access file "base/..."` | disk full / corruption | free space; restore → `infra-any-backupRecovery-manage` |
