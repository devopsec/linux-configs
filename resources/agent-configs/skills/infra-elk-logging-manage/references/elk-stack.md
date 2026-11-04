# Elastic Stack (Elasticsearch / Logstash / Kibana / Beats)

## Contents

1. When to choose it
2. Versions & install
3. Host prerequisites
4. Security & access
5. Ingest: Filebeat / Elastic Agent / Logstash
6. Data streams, templates, ILM
7. Queries (Query DSL, ES|QL)
8. Alerting
9. Troubleshooting

## 1. When to choose it

Full-text search over logs, rich Kibana analytics, existing Elastic estate. For "just ship VM logs and alert" on GCP, Cloud Logging (Ops Agent) is cheaper to run; for Grafana-centric stacks prefer Loki. License: Elastic License 2.0 / AGPL (verify fit).

## 2. Versions & install

- Reference pins checked 2026-10-28 against [Elastic Stack 9.5.5](https://www.elastic.co/blog/elastic-stack-9-5-5-released) and [8.19.23](https://www.elastic.co/blog/elastic-stack-8-19-23-released) release notes. Upgrade 8 → 9 only from the documented supported 8.19 path via Upgrade Assistant; confirm compatibility and exact package version before applying updates.
- Install from the signed Elastic repo (`rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch` + `/etc/yum.repos.d/elastic.repo`; apt: keyring + `signed-by=`). First start prints the `elastic` superuser password and an enrollment token — capture into Secret Manager immediately, don't paste into chat/tickets.
- Ports: 9200 (HTTP API), 9300 (transport), 5601 (Kibana), 5044 (Beats → Logstash). Firewall all to private sources.

## 3. Host prerequisites

```bash
sudo sysctl -w vm.max_map_count=262144     # persist in /etc/sysctl.d/99-elasticsearch.conf
# heap: ≤ 50% RAM and < ~31 GB (compressed oops); set in /etc/elasticsearch/jvm.options.d/heap.options
#   -Xms8g
#   -Xmx8g
# systemd override: LimitMEMLOCK=infinity if bootstrap.memory_lock: true
```

Disk watermarks default to 85/90/95% — keep data disks < 80%; use dedicated PD-SSD/Hyperdisk for hot nodes.

## 4. Security & access

- Security is on by default since 8.0 (TLS on HTTP + transport, auth). Upstream's `xpack.security.enabled=false` is **not acceptable** beyond a local throwaway container.
- Use **API keys** scoped per writer (Filebeat/Logstash) and reader (Grafana), not the `elastic` superuser:

```bash
curl --fail --silent --cacert "$ES_CA" --header "Authorization: ApiKey $ES_ADMIN_API_KEY" \
  --request POST "https://$ES_HOST:9200/_security/api_key" --header 'Content-Type: application/json' \
  --data '{"name":"filebeat-writer","role_descriptors":{"writer":{"cluster":["monitor","read_ilm","read_pipeline"],"indices":[{"names":["logs-*"],"privileges":["auto_configure","create_doc"]}]}}}'
```

- Kibana ↔ ES via service account token (`elasticsearch.serviceAccountToken`), stored in Kibana keystore (`kibana-keystore add`), not `kibana.yml`.

## 5. Ingest

Prefer **Elastic Agent** (Fleet-managed integrations: system, nginx, PostgreSQL, custom logs) or **Filebeat** → Elasticsearch directly with ingest pipelines; add **Logstash** only for heavy transforms/fan-out.

```yaml
# /etc/filebeat/filebeat.yml (excerpt)
filebeat.inputs:
  - type: filestream
    id: application
    paths: [/var/log/<service>/*.log]
    parsers:
      - multiline: { type: pattern, pattern: '^\w{3} +\d+ ', negate: true, match: after }
    fields: { service: <service> }
    fields_under_root: true
  - type: journald
    id: units
    include_matches.match: [ "_SYSTEMD_UNIT=<service>.service" ]
output.elasticsearch:
  hosts: ["https://<es-host>:9200"]
  api_key: "${ES_API_KEY}"            # from filebeat keystore or env, never literal
  ssl.certificate_authorities: ["/etc/filebeat/certs/ca.crt"]
```

(`type: log` input is deprecated → `filestream`.)

Logstash pipeline sketch (parse a generic service log, drop debug, scrub sensitive values):

```ruby
filter {
  grok { match => { "message" => "%{SYSLOGTIMESTAMP:ts} %{HOSTNAME:host} %{DATA:prog}\[%{POSINT:pid}\]: %{LOGLEVEL:level}: %{GREEDYDATA:msg}" } }
  if [level] == "DEBUG" { drop {} }
  mutate { gsub => [ "msg", "(?i)(token|password|api[_-]?key)=\S+", "\1=REDACTED" ] }
  date { match => ["ts", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss"] }
}
output {
  elasticsearch {
    hosts => ["https://<es-host>:9200"]
    api_key => "${ES_API_KEY}"
    data_stream => "true"
    data_stream_dataset => "kamailio"
    ssl_certificate_authorities => ["/etc/logstash/certs/ca.crt"]
  }
}
```

Store secrets with `logstash-keystore add ES_API_KEY`.

## 6. Data streams, templates, ILM

Use data streams (`logs-<dataset>-<namespace>`) instead of daily `logs-%{+YYYY.MM.dd}` indices.

```json
PUT _ilm/policy/logs-30d
{ "policy": { "phases": {
  "hot":    { "actions": { "rollover": { "max_primary_shard_size": "50gb", "max_age": "1d" } } },
  "warm":   { "min_age": "7d",  "actions": { "shrink": { "number_of_shards": 1 }, "forcemerge": { "max_num_segments": 1 } } },
  "delete": { "min_age": "30d", "actions": { "delete": {} } } } } }
```

Upstream's `"freeze": {}` action was removed in 8.0 — use the frozen tier via searchable snapshots (license-dependent) or just delete. Map IDs/levels as `keyword`; keep `message` as `match_only_text` to save space.

## 7. Queries

```json
GET logs-*/_search
{ "size": 20, "sort": [{ "@timestamp": "desc" }],
  "query": { "bool": { "filter": [
    { "term": { "service": "kamailio" } },
    { "term": { "log.level": "error" } },
    { "range": { "@timestamp": { "gte": "now-1h" } } } ] } } }
```

ES|QL (GA, often simpler):

```
FROM logs-* | WHERE service == "kamailio" AND @timestamp > NOW() - 1 hour
| STATS errors = COUNT(*) BY log.level, host.name | SORT errors DESC
```

Use `filter` context (cacheable) rather than `must` for exact matches.

## 8. Alerting

Kibana alerting rules (Elasticsearch query / log threshold) with connectors (PagerDuty, webhook) — connector secrets stored encrypted in Kibana; Watcher is legacy. Route to the same severities as `alerting-oncall.md`.

## 9. Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| cluster red/yellow | `GET _cluster/health`, `GET _cluster/allocation/explain` | replicas on single node → `number_of_replicas: 0`; disk watermark |
| indices read-only | disk > flood stage 95% | free disk, then `PUT _all/_settings {"index.blocks.read_only_allow_delete": null}` |
| ingest drops | Filebeat logs, `_ingest/pipeline/_simulate` | fix grok/pipeline |
| heap pressure / GC | `GET _nodes/stats/jvm` | right-size heap, fewer shards (aim 10–50 GB/shard) |
| too many shards | `GET _cat/shards?v` | ILM rollover by size, delete old data |
