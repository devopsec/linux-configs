# Rate limiting (pike and friends)

## pike

Typical concerns:

- `sampling_time_unit`, `reqs_density_per_unit`, `remove_latency`
- Per-IP vs per-method hooks in request route
- Response on hit: often `503` or custom code — **match platform ICD/docs**

## Platform GUI modules

Some trees rename or wrap pike as `rate_limiting` (GUI module):

- Keep backend Kamailio params and GUI field names in sync.
- Saving GUI config should update runtime without full restart when that was prior behavior.
- Migration: map old setting keys → new keys; do not drop user values silently.

## htable / counters

- Counter windows and expire timers must match documented policy.
- Avoid unbounded key growth; set sizes explicitly when touching table defs.

## Test sketch

1. Apply limit low in a lab cfg.
2. Send burst (sipp or project tool).
3. Confirm reject path + log line + GUI display if any.
