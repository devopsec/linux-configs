# Docker image build

## Dockerfile patterns

Python + uv (house default; matches `pyproject.toml` + `uv.lock`):

```dockerfile
# syntax=docker/dockerfile:<approved-frontend-version>@sha256:<approved-frontend-digest>
FROM ghcr.io/astral-sh/uv:0.13.6-python3.12-bookworm-slim@sha256:<approved-build-image-digest> AS build
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
# deps layer: cached until the lockfile changes
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked --no-dev --no-install-project
COPY . .
RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked --no-dev

FROM python:3.12.16-slim-bookworm@sha256:<approved-runtime-image-digest>
RUN groupadd -r -g 10001 app && useradd -r -u 10001 -g app -d /app app
WORKDIR /app
COPY --from=build --chown=app:app /app /app
ENV PATH="/app/.venv/bin:$PATH"
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; urllib.request.urlopen('http://localhost:8080/health', timeout=3)"]
CMD ["python", "-m", "myservice"]
```

Rules:
- Example pins: uv `0.13.6` and CPython `3.12.16` (checked 2026-10-28); resolve and record the exact base-image digests before release.
- Pin the Dockerfile frontend and all base images by exact version/digest; never use floating tags for release images.
- Order layers least → most frequently changing; copy lockfiles before source.
- Exec-form `CMD`/`ENTRYPOINT` (JSON array) so PID 1 receives SIGTERM; add `--init` or `tini` if the app does not reap children.
- `COPY` not `ADD` (no remote URLs / auto-extract surprises).
- `.dockerignore`: `.git`, `.venv`, `__pycache__`, `*.pem`, `*.key`, `resources/keys/`, `.env*`.
- Build secrets: `RUN --mount=type=secret,id=pip_token ...` + `docker build --secret id=pip_token,env=PIP_TOKEN` — never `ARG TOKEN`.
- Use the image's health probe without curl if curl is not in the image (as above).

## Build

```bash
docker build -t myapp:dev .
docker build --target build -t myapp:build .          # stop at a stage
docker build --platform linux/amd64 -t myapp:amd64 .
docker buildx create --name multi --use               # once
docker buildx build --platform linux/amd64,linux/arm64 \
  -t "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/myapp:${TAG}" --push .
docker build --no-cache --pull -t myapp:fresh .        # bypass stale base
hadolint Dockerfile                                    # lint
```

