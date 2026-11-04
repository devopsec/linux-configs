# Docker Compose (v2 plugin)

- File name: `compose.yaml` (preferred) or `docker-compose.yml`. The top-level `version:` key is **obsolete** — omit it.
- Command: `docker compose ...` (plugin). Prefer the plugin over the legacy standalone `docker-compose` command.
- Podman: `podman compose` (wraps `docker-compose` or `podman-compose`, install from distro packages) or Docker Compose against `podman.socket`.

## Baseline stack (PostgreSQL + app, no literal secrets)

```yaml
name: myapp
x-common: &common
  restart: unless-stopped
  logging:
    driver: json-file
    options: { max-size: "10m", max-file: "3" }

services:
  app:
    <<: *common
    build: { context: ., target: runtime }
    image: ${IMAGE:-myapp:dev}
    ports: ["127.0.0.1:8080:8080"]
    environment:
      DATABASE_HOST: db
      DATABASE_USER: ${DB_USER:?set DB_USER in .env}
      DATABASE_PASSWORD_FILE: /run/secrets/db_password
    secrets: [db_password]
    depends_on:
      db: { condition: service_healthy }
    networks: [frontend, backend]

  db:
    <<: *common
    image: "${POSTGRES_IMAGE:?set a digest-pinned POSTGRES_IMAGE}"
    environment:
      POSTGRES_USER: ${DB_USER:?}
      POSTGRES_DB: myapp
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets: [db_password]
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./init-sql:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \"$${POSTGRES_USER}\" -d myapp"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [backend]

volumes:
  pgdata:

networks:
  frontend:
  backend:
    internal: true          # no egress/ingress outside the stack

secrets:
  db_password:
    file: ./secrets/db_password   # gitignored; or `environment: DB_PASSWORD`
```

Gotchas:
- `$$` escapes `$` for the container shell; `${VAR:?msg}` fails fast when unset.
- `.env` beside compose file is read for **interpolation**; `env_file:` passes vars into the container. Keep both out of git.
- `depends_on` without `condition: service_healthy` only orders start-up, it does not wait for readiness.
- Init scripts in `/docker-entrypoint-initdb.d` run **only on an empty data volume**.
- Ports default to `0.0.0.0`; bind to `127.0.0.1` for dev DBs.
- `deploy.resources.limits` is honoured by `docker compose` (non-swarm) for cpus/memory.

## Overrides, profiles, watch

```bash
docker compose up -d                                        # + compose.override.yaml automatically
docker compose -f compose.yaml -f compose.prod.yaml config  # render merged config (validate)
docker compose -f compose.yaml -f compose.prod.yaml up -d
COMPOSE_FILE=compose.yaml:compose.prod.yaml docker compose up -d
docker compose --profile debug up -d                        # services with profiles: [debug]
docker compose watch                                        # when supported by the pinned Compose plugin
```

```yaml
services:
  app:
    develop:
      watch:
        - { action: sync, path: ./src, target: /app/src }
        - { action: rebuild, path: uv.lock }
```

## Lifecycle

```bash
docker compose ps; docker compose logs -f --tail=100 app
docker compose exec app /bin/sh
docker compose run --rm app python -m pytest -q
docker compose pull && docker compose up -d                # update images
docker compose up -d --build --force-recreate app
docker compose down                                         # keeps volumes
# DANGER (data loss): docker compose down -v --rmi all
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Service name does not resolve | same network? `docker compose exec app getent hosts db` |
| Volume permission denied | match container UID; on SELinux hosts add `:Z`/`:z` to bind mounts |
| Changes not visible | rebuild (`--build`), check bind mount path, `watch` rules |
| Port already in use | `ss -ltnp 'sport = :5432'`; change host port |
