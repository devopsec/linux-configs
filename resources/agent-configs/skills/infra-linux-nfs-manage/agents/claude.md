# Claude Specifics for Infra Linux Nfs Manage

## Context & Tuning
- Follow the NFS workload-fit, identity, and hard-mount guidance for the task.
- Keep provider provisioning separate from Linux mount configuration.

## Instructions Overrides
- Ask before broadening exports or changing production mount semantics.
- Never expose credentials or private network/share details.
