# Claude specifics — infra-redis-server-administer

- Clarify whether Redis is a cache, durable store, queue, or coordination mechanism before changing policy.
- Require explicit approval for destructive commands and production failover.
- Never expose authentication material in commands or output.
