# PostgreSQL monitoring & maintenance

## Contents

1. Connections & activity
2. Locks
3. Slow queries (`pg_stat_statements`, `EXPLAIN`)
4. Cache, size, indexes
5. Vacuum, bloat, wraparound
6. Partitions & `pg_cron`
7. Exporter / alert hooks

All queries are read-only unless marked **WRITE**. Run with `psql -X -v ON_ERROR_STOP=1`.

## 1. Connections & activity

```sql
SELECT state, wait_event_type, count(*) FROM pg_stat_activity
WHERE backend_type = 'client backend' GROUP BY 1, 2 ORDER BY 3 DESC;

SELECT count(*) AS used, current_setting('max_connections')::int AS max FROM pg_stat_activity;

-- long-running / idle-in-transaction
SELECT pid, usename, application_name, client_addr, state,
       now() - xact_start AS xact_age, now() - query_start AS query_age,
       left(query, 120) AS query
FROM pg_stat_activity
WHERE state <> 'idle' AND (now() - xact_start > interval '5 min' OR state = 'idle in transaction')
ORDER BY xact_age DESC NULLS LAST;
```

**WRITE** — stop a query: `SELECT pg_cancel_backend(<pid>);` (gentle) → `pg_terminate_backend(<pid>)` (kills session). Confirm the pid/query with the user first.

## 2. Locks

```sql
-- who blocks whom
SELECT a.pid AS blocked_pid, left(a.query, 80) AS blocked_query,
       b.pid AS blocking_pid, left(b.query, 80) AS blocking_query,
       now() - b.xact_start AS blocking_xact_age
FROM pg_stat_activity a
JOIN LATERAL unnest(pg_blocking_pids(a.pid)) AS bp(pid) ON true
JOIN pg_stat_activity b ON b.pid = bp.pid;
```

Classic incident: a DDL waiting for `AccessExclusiveLock` behind a long transaction queues **all** later readers. Fix: `lock_timeout` on DDL sessions (see migrations-safety).

## 3. Slow queries

Enable once: `shared_preload_libraries = 'pg_stat_statements'` (restart), then `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;`.

```sql
SELECT queryid, calls, round(total_exec_time::numeric, 0) AS total_ms,
       round(mean_exec_time::numeric, 1) AS mean_ms, rows,
       round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 1) AS hit_pct,
       left(query, 120) AS query
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 15;
-- reset window (WRITE): SELECT pg_stat_statements_reset();
```

`EXPLAIN (ANALYZE, BUFFERS, SETTINGS) <query>;` — **ANALYZE executes the query**; wrap DML in `BEGIN; … ROLLBACK;`. Look for: Seq Scan on large tables with selective filters, row-estimate vs actual off by 10×+ (→ `ANALYZE <table>` or extended statistics), `Sort Method: external merge` (→ `work_mem`), nested loops over large outer sets.

## 4. Cache, size, indexes

```sql
SELECT datname, round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
       xact_commit, xact_rollback, deadlocks, temp_bytes
FROM pg_stat_database WHERE datname IS NOT NULL;

SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total,
       pg_size_pretty(pg_indexes_size(relid)) AS indexes
FROM pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 15;

-- unused indexes (check on replicas too; stats reset on restart/failover)
SELECT s.relname, s.indexrelname, s.idx_scan, pg_size_pretty(pg_relation_size(s.indexrelid)) AS size
FROM pg_stat_user_indexes s JOIN pg_index i USING (indexrelid)
WHERE s.idx_scan = 0 AND NOT i.indisunique AND NOT i.indisprimary
ORDER BY pg_relation_size(s.indexrelid) DESC;

-- tables doing many seq scans
SELECT relname, seq_scan, seq_tup_read, idx_scan, n_live_tup
FROM pg_stat_user_tables WHERE seq_scan > 0 ORDER BY seq_tup_read DESC LIMIT 15;
```

Cache hit < 99% on OLTP → more `shared_buffers`/RAM or fix the scanning query.

## 5. Vacuum, bloat, wraparound

```sql
SELECT relname, n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / greatest(n_live_tup, 1), 1) AS dead_pct,
       last_autovacuum, last_autoanalyze, autovacuum_count
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 15;

-- wraparound headroom (alert at > 1e9; hard stop near 2^31)
SELECT datname, age(datfrozenxid) AS xid_age FROM pg_database ORDER BY 2 DESC;

-- what holds back xmin (blocks cleanup everywhere)
SELECT 'backend' AS src, pid::text, age(backend_xmin) FROM pg_stat_activity WHERE backend_xmin IS NOT NULL
UNION ALL SELECT 'slot', slot_name, age(xmin) FROM pg_replication_slots WHERE xmin IS NOT NULL
UNION ALL SELECT 'prepared', gid, age(transaction) FROM pg_prepared_xacts
ORDER BY 3 DESC;

SELECT * FROM pg_stat_progress_vacuum;
```

Tuning hot/large tables (per table, **WRITE**):

```sql
ALTER TABLE <big_table> SET (autovacuum_vacuum_scale_factor = 0.02,
                             autovacuum_analyze_scale_factor = 0.01,
                             autovacuum_vacuum_cost_limit = 2000);
```

Global: `autovacuum_max_workers` 3–6, `autovacuum_vacuum_cost_limit` 1000–2000 on SSD; PG18 adds `autovacuum_vacuum_max_threshold`.
Manual: `VACUUM (VERBOSE, ANALYZE) <table>;` is online. `VACUUM FULL`/`CLUSTER` take `ACCESS EXCLUSIVE` — use `pg_repack` (extension) instead, or PG19 `REPACK … CONCURRENTLY` once on 19.
Index bloat: `REINDEX INDEX CONCURRENTLY <idx>;` (online; leaves an `_ccnew` invalid index on failure — drop it).

## 6. Partitions & `pg_cron`

Declarative range partitioning (e.g. CDR/event tables by day/month) keeps vacuum and retention cheap:

```sql
CREATE TABLE events (id bigint GENERATED ALWAYS AS IDENTITY, created_at timestamptz NOT NULL, …)
  PARTITION BY RANGE (created_at);
CREATE TABLE events_default PARTITION OF events DEFAULT;
CREATE TABLE IF NOT EXISTS events_2026_11 PARTITION OF events
  FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
```

- Pre-create future partitions (job or `pg_partman`); rows landing in `DEFAULT` make later `CREATE … PARTITION OF` for that range fail until moved out — monitor `count(*)` of the default partition.
- Retention: `ALTER TABLE events DETACH PARTITION events_2025_01 CONCURRENTLY;` then archive/`DROP` (**WRITE, destructive** — backup/export first). `CONCURRENTLY` is refused when the parent has a `DEFAULT` partition — then plain `DETACH` (brief `ACCESS EXCLUSIVE`, use `lock_timeout`).
- Indexes created on the parent propagate; for online creation on big parents: create `ON ONLY parent`, then `CONCURRENTLY` per partition, then `ALTER INDEX … ATTACH PARTITION`.

`pg_cron` (needs `shared_preload_libraries` and `cron.database_name`):

```sql
SELECT cron.schedule('create-partitions', '5 0 * * *', $$CALL <schema>.create_future_partitions()$$);
SELECT jobid, jobname, schedule, active FROM cron.job;
SELECT jobid, status, return_message, start_time FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;
```

Alert on `status = 'failed'` rows; `job_run_details` grows forever — schedule its own purge.

## 7. Exporter / alert hooks

- Exporter role: `CREATE ROLE pg_exporter LOGIN IN ROLE pg_monitor;` (password from Secret Manager).
- `postgres_exporter` (prometheus-community) on VMs; Cloud SQL → Cloud Monitoring metrics (`cloudsql.googleapis.com/database/postgresql/*`) + Query Insights.
- Alert minimums: connections > 80% max, replication lag > 60s, xid age > 1e9, dead_pct > 20% on big tables, WAL retained by slot > threshold, disk > 80%, failed `pg_cron` jobs. Dashboards/alert routing → `infra-observability-any-manage`.
