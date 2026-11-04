# Testing Guidelines

Guidelines for implementing and running Integration, E2E, and Load tests.

## Test Types
- **Unit**: Fast, isolated logic checks.
- **Integration**: Component interaction checks.
- **E2E**: Full system workflow validation.
- **Load**: Benchmarking and performance under stress.

## Workflow
- IF `<project-root>/testing/README.md` exists → REFERENCE it and follow its layout (`testing/e2e/config.sh` env check before E2E; new integration tests under `testing/integ/`).
- ELSE → use the project's own test layout and runner (detect from `pytest.ini`/`pyproject.toml`, `package.json`, `Makefile`, CI config); never create a `testing/` tree the project does not have.
- Always verify required env vars/fixtures before running E2E tests; add an integration test for every new feature.
