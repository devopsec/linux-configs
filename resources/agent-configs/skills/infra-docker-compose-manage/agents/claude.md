# Claude specifics - infra-docker-compose-manage

## Context & Tuning
- Load the Compose reference only for the files or lifecycle issue in scope.
- Confirm which environment and override files are active before evaluating interpolation.
- Preserve data volumes by default; call out any operation that would remove them.
- Redact environment-derived values when reporting diagnostics.
