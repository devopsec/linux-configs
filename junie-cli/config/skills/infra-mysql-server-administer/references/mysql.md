# MySQL / MariaDB

## Contents

1. Versions & install
2. Credentials
3. Users & grants
4. Tuning (`my.cnf`)
5. Replication (GTID)
6. Monitoring
7. Backups (pointer)
8. Containers (dev)
9. Troubleshooting

## 1. Versions & install

- Reference pins checked 2026-10-28 against [MySQL 8.4.13 downloads](https://dev.mysql.com/downloads/mysql/8.4.html) and [9.7.4 release notes](https://dev.mysql.com/doc/relnotes/mysql/9.7/en/news-9-7-4.html): **8.4.13 LTS** and **9.7.4 LTS**. Use the LTS branch supported by the application; MariaDB releases have a separate support lifecycle. Cloud SQL for MySQL → `infra-gcp-cloudSql-manage`.
- 8.4 removed `mysql_native_password` by default and `SHOW MASTER STATUS` / `CHANGE MASTER` syntax — use `caching_sha2_password`, `SHOW BINARY LOG STATUS`, `CHANGE REPLICATION SOURCE TO`.

```bash
# RHEL-family: configure the signed Oracle MySQL repo for the selected LTS, then pin the exact NEVRA
sudo dnf list --showduplicates mysql-community-server
sudo dnf install -y 'mysql-community-server-<exact-8.4.13-or-9.7.4-nevra>'
# Debian/Ubuntu: use the signed MySQL repo; pin the exact package version (default-mysql-server may be MariaDB)
sudo apt-cache madison mysql-community-server
sudo apt install -y 'mysql-community-server=<exact-8.4.13-or-9.7.4-package-version>'
sudo mysql_secure_installation              # interactive: run manually, not from agents
```

SELinux: custom datadir → `semanage fcontext -a -t mysqld_db_t '<dir>(/.*)?'; restorecon -Rv <dir>`.

## 2. Credentials

Never `-p<password>` on the command line (visible in `ps`). Use `MYSQL_PWD` sparingly, or better a 0600 option file passed explicitly:

```bash
umask 077; printf '[client]\nuser=%s\npassword=%s\nhost=%s\n' "$DB_USER" "$DB_PASSWORD" "$DB_HOST" > "$TMPDIR/my.cnf"
mysql --defaults-extra-file="$TMPDIR/my.cnf" -e 'SELECT CURRENT_USER();'
rm -f "$TMPDIR/my.cnf"
```

Or `mysql_config_editor set --login-path=<name> --host=… --user=… --password` (obfuscated `.mylogin.cnf`).

## 3. Users & grants

```sql
CREATE DATABASE app CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER 'app_rw'@'<app-host-pattern>' IDENTIFIED WITH caching_sha2_password BY '<from-secret-manager>' REQUIRE SSL;
GRANT SELECT, INSERT, UPDATE, DELETE ON app.* TO 'app_rw'@'<app-host-pattern>';
CREATE ROLE 'readonly'; GRANT SELECT ON app.* TO 'readonly';
GRANT 'readonly' TO 'analyst'@'<analyst-host-pattern>'; SET DEFAULT ROLE ALL TO 'analyst'@'<analyst-host-pattern>';
SHOW GRANTS FOR 'app_rw'@'<app-host-pattern>';
```

`FLUSH PRIVILEGES` is only needed after direct edits of grant tables. Avoid `'%'` hosts and `GRANT ALL ON *.*`.

## 4. Tuning (`/etc/my.cnf.d/*.cnf` RHEL, `/etc/mysql/mysql.conf.d/` Debian)

```ini
[mysqld]
bind-address                   = <private-ip>
max_connections                = 300
innodb_buffer_pool_size        = 4G      # 60–75% RAM on dedicated host
innodb_redo_log_capacity       = 2G      # 8.0.30+ (replaces innodb_log_file_size)
innodb_flush_log_at_trx_commit = 1       # durability; 2 = faster, up to 1s loss
sync_binlog                    = 1
innodb_flush_method            = O_DIRECT
innodb_io_capacity             = 2000
slow_query_log                 = ON
long_query_time                = 1
server_id                      = <unique>
log_bin                        = mysql-bin
binlog_expire_logs_seconds     = 604800
gtid_mode                      = ON
enforce_gtid_consistency       = ON
require_secure_transport       = ON
```

Most InnoDB sizes are dynamic in 8.x: `SET PERSIST innodb_buffer_pool_size = …;` (no restart).

## 5. Replication (GTID)

```sql
-- source
CREATE USER 'replicator'@'<replica-ip>' IDENTIFIED BY '<from-secret-manager>' REQUIRE SSL;
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'<replica-ip>';
-- replica (seeded from a consistent backup / CLONE plugin)
CHANGE REPLICATION SOURCE TO SOURCE_HOST='<source-private-host>', SOURCE_USER='replicator',
  SOURCE_PASSWORD='<from-secret-manager>', SOURCE_AUTO_POSITION=1, SOURCE_SSL=1;
START REPLICA;
SHOW REPLICA STATUS\G   -- Replica_IO_Running/SQL_Running = Yes, Seconds_Behind_Source ≈ 0
SET PERSIST super_read_only = ON;
```

Prefer `performance_schema.replication_applier_status_by_worker` for errors. Don't "skip" errors blindly — find the divergent row.

## 6. Monitoring

```sql
SHOW GLOBAL STATUS LIKE 'Threads_%';
SELECT * FROM sys.statement_analysis ORDER BY total_latency DESC LIMIT 10;
SELECT * FROM sys.schema_unused_indexes;
SELECT * FROM sys.innodb_lock_waits\G
SELECT table_name, ROUND((data_length+index_length)/1024/1024) AS mb
FROM information_schema.tables WHERE table_schema = 'app' ORDER BY mb DESC LIMIT 15;
```

Exporter: `mysqld_exporter` with a `PROCESS, REPLICATION CLIENT, SELECT` user.

## 7. Backups

`mysqldump --single-transaction --routines --triggers --events --set-gtid-purged=AUTO`, `mysqlsh util.dumpInstance()`, or Percona XtraBackup 8.4 for physical. Scheduling/retention/restore drills → `infra-any-backupRecovery-manage`.

## 8. Containers (dev)

```yaml
services:
  mysql:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/mysql_root
      MYSQL_DATABASE: app
    secrets: [mysql_root]
    ports: ["127.0.0.1:3306:3306"]
    volumes: ["mysql_data:/var/lib/mysql"]
secrets:
  mysql_root: { file: ./secrets/mysql_root.txt }
volumes: { mysql_data: {} }
```

Dropped upstream's phpMyAdmin sidecar (exposed root creds on 8080).

## Online migration notes

On MySQL 8.4.13 or 9.7.4 (reference pins checked 2026-10-28), specify `ALGORITHM=INSTANT` for supported column changes or `ALGORITHM=INPLACE, LOCK=NONE` for supported operations so unsupported requests fail instead of silently copying a table. For large tables, evaluate `gh-ost` or `pt-online-schema-change` with the application's replication and foreign-key constraints in mind.

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Too many connections` | leaks/no pooling | `SHOW PROCESSLIST`, ProxySQL/app pool, `wait_timeout` |
| `Lock wait timeout exceeded` | long txn holds row locks | `sys.innodb_lock_waits`, kill blocker (confirm first) |
| replica SQL thread stopped | divergence / duplicate key | `SHOW REPLICA STATUS` error, rebuild replica if unsure |
| `Authentication plugin … cannot be loaded` | old client vs `caching_sha2_password` | upgrade client/connector |
| high IO with frequent flushes | redo too small | raise `innodb_redo_log_capacity` |
