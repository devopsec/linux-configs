# PostgreSQL schema migration safety

Goal: no long `ACCESS EXCLUSIVE` locks, every step reversible, app compatible with both old and new schema during deploy (expand → migrate → contract).

## Session guard rails (every migration)

```sql
SET lock_timeout = '3s';          -- fail fast instead of queueing all traffic behind us
SET statement_timeout = '15min';  -- raise only for known long steps
SET idle_in_transaction_session_timeout = '1min';
```

Retry lock-timeout failures with backoff (migration tool or wrapper loop) rather than raising `lock_timeout`.

## Operation cheat sheet

| Change | Unsafe | Safe pattern |
|---|---|---|
| Add index | `CREATE INDEX` (blocks writes) | `CREATE INDEX CONCURRENTLY` — not inside a transaction; on failure `DROP INDEX CONCURRENTLY` the invalid one |
| Add column | with volatile default on PG<11 | `ADD COLUMN … DEFAULT <constant>` is metadata-only on PG11+; volatile defaults (`now()`, `gen_random_uuid()`) still rewrite → add nullable, backfill, then set default |
| `NOT NULL` | `SET NOT NULL` directly (full scan under lock) | `ADD CONSTRAINT c CHECK (col IS NOT NULL) NOT VALID` → `VALIDATE CONSTRAINT c` → `SET NOT NULL` (PG12+ uses the valid check, no scan) → drop check |
| Foreign key | `ADD FOREIGN KEY` (locks both tables + scan) | `ADD CONSTRAINT … NOT VALID` then `VALIDATE CONSTRAINT` (weaker lock) |
| Unique | `ADD UNIQUE` | `CREATE UNIQUE INDEX CONCURRENTLY` then `ADD CONSTRAINT … UNIQUE USING INDEX` |
| Change type | `ALTER COLUMN TYPE` (rewrite) | new column + dual-write/trigger + backfill + swap; safe exceptions: `varchar(n)`→larger/`text` |
| Rename column/table | rename while old code runs | add new + view/compat layer, deploy code, then drop old (contract step) |
| Drop column | drop while code still reads it | stop reading in code first, deploy, then drop |
| Big backfill | one `UPDATE` of millions of rows | batches of 1k–10k by PK range, commit each, sleep; watch replication lag and dead tuples |
| Enum value | — | `ALTER TYPE … ADD VALUE` is cheap; inside a transaction (PG12+) the new value is usable only after commit |

Batch backfill skeleton:

```sql
-- repeat until 0 rows updated; driver loop in app/migration tool
UPDATE <t> SET new_col = <expr>
WHERE id IN (SELECT id FROM <t> WHERE new_col IS NULL ORDER BY id LIMIT 5000);
```

## Process checklist

1. Migration file in VCS (Alembic / plain numbered SQL, whatever the repo uses); never ad-hoc DDL in prod.
2. Run against a fresh copy of prod schema (`pg_dump --schema-only` into a scratch DB) and a staging DB with realistic volume; time each step.
3. Confirm a restorable backup / PITR window → `infra-any-backupRecovery-manage`. On Cloud SQL take an on-demand backup first.
4. Write the down-migration (or explicit "irreversible — restore from backup" note).
5. Apply in a low-traffic window if any step takes a strong lock; monitor locks (`pg_blocking_pids`) and replication lag while running.
6. Post-checks: `\d+ <table>`, invalid indexes `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;`, app error rate.

## Destructive steps

`DROP TABLE`, `DROP COLUMN`, `TRUNCATE`, `DELETE` without `WHERE`: **label them, require explicit user approval**, run first as `BEGIN; … ; SELECT count(*) …; ROLLBACK;` to show impact. Prefer rename-to-`_deprecated_<date>` and drop in a later release.

