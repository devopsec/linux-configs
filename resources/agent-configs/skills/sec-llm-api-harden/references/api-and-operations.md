# API layer, consumption limits, logging, retention

Derived from upstream `ai-security-hardening` and `llm-app-security` (MIT). Fixed: undefined `SECRET_KEY` and HS256 shared-secret JWTs → asymmetric/issuer-verified tokens; in-process rate limiter (breaks with multiple workers) → shared store; never log raw prompts by default.

## Contents

1. Authentication
2. Rate limits, token budgets, cost caps (LLM10)
3. Gateway / proxy limits
4. Security logging
5. Alerts
6. Retention
7. Model access

## 1. Authentication

- Every endpoint authenticated; identify the *end user* and tenant, not just the calling service.
- Prefer OIDC/JWT verified against the issuer's JWKS (RS256/ES256), checking `iss`, `aud`, `exp`; or Google-signed ID tokens (IAP / Cloud Run auth) on GCP. Service-to-service: short-lived tokens, workload identity / service accounts, no static keys.
- Upstream model provider keys: Secret Manager → env at start-up; per-environment keys with spend limits set at the provider; rotate on schedule and on any leak.

```python
import os
import jwt                                  # PyJWT
from jwt import PyJWKClient

JWKS = PyJWKClient(os.environ["OIDC_JWKS_URL"])

def verify(token: str) -> dict:
    key = JWKS.get_signing_key_from_jwt(token).key
    return jwt.decode(token, key, algorithms=["RS256", "ES256"],
                      audience=os.environ["OIDC_AUDIENCE"], issuer=os.environ["OIDC_ISSUER"])
```

## 2. Rate limits, token budgets, cost caps

Use a shared store (Redis/Memorystore or PostgreSQL) so limits hold across workers and instances:

```python
import os, time, redis
r = redis.Redis.from_url(os.environ["REDIS_URL"])

def take(user_id: str, limit: int = 60, window_s: int = 60) -> None:
    key = f"rl:{user_id}:{int(time.time() // window_s)}"
    n = r.incr(key)
    if n == 1:
        r.expire(key, window_s)
    if n > limit:
        raise RateLimited(retry_after=window_s)

def charge_tokens(user_id: str, tokens: int, daily_budget: int = 200_000) -> None:
    key = f"tok:{user_id}:{time.strftime('%Y%m%d')}"
    used = r.incrby(key, tokens)
    r.expire(key, 2 * 86400)
    if used > daily_budget:
        raise BudgetExceeded()
```

- Check *before* the model call using an estimate (input tokens + `max_tokens`), reconcile after with actual usage.
- Per-tenant daily cost cap computed from token usage × model price table; hard stop + alert at 100%, warn at 80%.
- Cap `max_tokens`, input length, number of tool iterations per request, and request timeout; reject huge uploads early.
- Rate-limit on authenticated user/tenant, not only IP.

## 3. Gateway / proxy limits

NGINX in front of the app (adapt zones/limits):

```nginx
limit_req_zone $http_authorization zone=llm_per_key:10m rate=30r/m;
server {
  client_max_body_size 256k;
  location /v1/chat {
    limit_req zone=llm_per_key burst=10 nodelay;
    proxy_read_timeout 120s;
    proxy_pass http://localhost:8000;
  }
}
```

GCP: Cloud Armor rate-based rules on the HTTPS load balancer, or API Gateway / Apigee quotas. Keep app-level per-user limits regardless.

## 4. Security logging

One structured JSON event per request (stdout → Cloud Logging):

`ts, request_id, tenant_id, user_id (pseudonymous), route, model, input_tokens, output_tokens, cost, latency_ms, tool_calls[name,result], injection_hits, canary_hit, moderation_flags, blocked_reason`

- **No raw prompts/completions by default** (PII, secrets). If needed for debugging, sample, scrub (Presidio/DLP), store in a restricted bucket/dataset with short TTL.
- Log sink to BigQuery for analysis; restrict dataset access; partition by day with expiration.

## 5. Alerts (Cloud Monitoring log-based metrics or Prometheus)

| Alert | Condition (starting point) |
|---|---|
| Injection spike | injection_hits rate > 5× 7-day baseline for 10m |
| Canary leak | any `canary_hit=true` → page |
| Cost anomaly | tenant hourly cost > 3× baseline, or > 80% of daily cap |
| Token abuse | single user > p99 tokens/hour |
| Tool denial spike | denied tool calls rate jump (probing) |
| Moderation flags | flagged output rate > threshold |

Keep label cardinality low (tenant, route — never raw user ids or prompt text as metric labels).

## 6. Retention

| Data | Default retention | Notes |
|---|---|---|
| Security event logs (no content) | 90–400 days | per compliance needs (`sec-compliance-framework-assess`) |
| Sampled scrubbed prompts | ≤ 30 days | restricted access |
| Conversation history | product-defined, TTL enforced | user-deletable |
| Embeddings of user content | lifetime of source doc | delete with source |

Automate purge jobs (BigQuery table/partition expiration, PostgreSQL scheduled deletes, Redis TTL) and log purge results.

## 7. Model access

- Allowlist of approved models/versions per environment; reject others at the gateway.
- Pin model versions; re-run evals before upgrading.
- Self-hosted models: verify artifact hashes and scan before serving; isolate serving network (ingress only from the app, no internet egress). Supply chain details → `sec-supplyChain-any-manage`.
