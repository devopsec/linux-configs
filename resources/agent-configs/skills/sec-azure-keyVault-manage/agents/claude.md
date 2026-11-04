# Claude Specifics for Sec Azure Keyvault Manage

## Operating notes

- Follow SAD KITTI and retrieve only the Key Vault section relevant to the task.
- Prefer managed identities and RBAC; report identifiers and access metadata, not secret contents.
- Obtain explicit approval before purge, deletion, or key/retention changes with recovery impact.
