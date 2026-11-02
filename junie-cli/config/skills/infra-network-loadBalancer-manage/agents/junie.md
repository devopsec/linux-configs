# Junie CLI Specifics for Infra Network Loadbalancer Manage

## Context & Tuning
- Execute SAD KITTI config selection and load only the matching GCP backend/health-check guidance.
- Request protocol, region, source scope, health port, and backend values at runtime.

## Instructions Overrides
- No commits or production cutovers without explicit approval and rollback steps.
- Redact private addresses, project IDs, and sensitive traffic details.
