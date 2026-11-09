# Evidence-gathering commands (read-only unless marked CHANGES STATE)

Adjust paths for the distro/container. Prefer absolute paths; in containers use `podman exec <name> ...` / `docker exec`.

## Identify what is running

```bash
nginx -v; nginx -V 2>&1 | tr ' ' '\n' | grep -E '^--with|^--add'   # version and modules (stub_status, realip, debug, http_v2, lua)
nginx -T 2>&1 | head -n 400                                         # effective config (redact secrets before sharing)
ps -o pid,ppid,user,lstart,args -C nginx                            # master/worker start times vs config mtime
pgrep -f 'nginx: worker' | tr '\n' ' '
systemctl status nginx --no-pager; journalctl -u nginx -n 100 --no-pager
```

## Error log summary

```bash
# top error patterns in the window (strip variable parts)
sed -E 's/^[0-9/ :]+ \[(\w+)\] [0-9#]+: (\*[0-9]+ )?/\1 /; s/client: [^,]+,.*//' /var/log/nginx/error.log | sort | uniq -c | sort -rn | head -20
# first occurrence of a pattern
grep -n -m1 'upstream timed out' /var/log/nginx/error.log
# alerts/crits only
grep -E '\[(alert|crit|emerg)\]' /var/log/nginx/error.log | tail -50
```

## Access log summary (combined format: status is field 9)

```bash
awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn
awk '$9 ~ /^5/ {print $7}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head      # 5xx by path
# with a custom log_format that has rt= urt= fields (see dev-nginx-config-manage recipes)
awk '{for(i=1;i<=NF;i++) if($i ~ /^rt=/){sub("rt=","",$i); if($i+0>1) c++}} END{print c " requests slower than 1s"}' access.log
goaccess /var/log/nginx/access.log --log-format=COMBINED         # interactive/HTML report
ngxtop -l /var/log/nginx/access.log                               # live top by path/status (pip package)
```

Useful fields to add to the log format: `$request_time`, `$upstream_connect_time`, `$upstream_header_time`, `$upstream_response_time`, `$upstream_addr`, `$upstream_status`, `$request_id`, `$ssl_protocol`, `$ssl_cipher`.

## Connections and sockets

```bash
curl -s http://localhost/nginx_status                  # needs stub_status ACL with allow 127.0.0.1 AND ::1 (or use curl -4)
ss -s                                                  # totals, TIME_WAIT/estab
ss -ltn '( sport = :443 or sport = :80 )'              # LISTEN: Recv-Q = accept queue now, Send-Q = backlog size
ss -tn state established '( dport = :9000 )' | wc -l   # connections to the upstream port
ss -tn state time-wait | wc -l
ss -tnp | grep nginx | awk '{print $1,$2,$3,$4,$5}' | head
nstat -az TcpExtListenOverflows TcpExtListenDrops TcpExtTCPTimeouts   # kernel counters; compare two samples
```

## File descriptors and limits

```bash
for p in $(pgrep -f 'nginx: worker'); do echo -n "$p fds="; ls /proc/$p/fd | wc -l; grep -i 'open files' /proc/$p/limits; done
systemctl show nginx -p LimitNOFILE
sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog net.ipv4.ip_local_port_range fs.file-max
grep -E 'worker_(connections|rlimit_nofile|processes)' <(nginx -T 2>/dev/null)
```

Rule of thumb check: `worker_rlimit_nofile` should be at least 2 x `worker_connections` for a proxy (client + upstream sockets).

## Upstream and network checks

```bash
curl -sS -o /dev/null -w 'connect=%{time_connect} ttfb=%{time_starttransfer} total=%{time_total} code=%{http_code}\n' http://UPSTREAM:PORT/health
nc -vz UPSTREAM PORT
getent hosts UPSTREAM; dig +short UPSTREAM          # DNS as nginx sees it (nginx resolves static names at start/reload)
```

## TLS

```bash
openssl s_client -connect HOST:443 -servername NAME -tls1_2 </dev/null 2>&1 | sed -n '1,25p'
openssl s_client -connect HOST:443 -servername NAME </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
openssl x509 -noout -modulus -in cert.pem | md5sum; openssl rsa -noout -modulus -in key.pem | md5sum   # must match
curl -sv https://HOST/ -o /dev/null 2>&1 | grep -E 'SSL|TLS|subject|expire|issuer'
```

## SELinux / AppArmor

```bash
getenforce; getsebool httpd_can_network_connect httpd_can_network_relay
ausearch -m avc -ts recent | tail
# CHANGES STATE (needs approval): setsebool -P httpd_can_network_connect 1
aa-status | grep -i nginx
```

## Deep dives (use sparingly, with approval)

```bash
# debug log (needs a --with-debug build; very verbose). Scope to one client:
#   events { debug_connection 192.0.2.10; }   error_log /tmp/nginx-debug.log debug;   -> reload (CHANGES STATE)
strace -f -tt -T -e trace=network,epoll_wait -p <worker-pid> -o /tmp/nginx.strace      # short, low traffic only
tcpdump -nn -i any -s 96 'tcp port 9000' -w /tmp/up.pcap                                # headers only, time-boxed
perf top -p <worker-pid>                                                                 # CPU hot spots (nginx C level)
```

## Crash and reload checks

```bash
grep -E 'exited on signal|core dumped' /var/log/nginx/error.log | tail
ps -ef | grep 'worker process is shutting down'      # old workers kept alive by long connections
nginx -t && echo ok                                   # does not prove the running process loaded it
# graceful reload is CHANGES STATE: nginx -s reload   (then re-check error.log)
```
