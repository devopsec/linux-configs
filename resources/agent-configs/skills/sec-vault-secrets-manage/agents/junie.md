# Junie CLI Specifics for Sec Vault Secrets Manage

## Operating notes

- Execute SAD KITTI branches and load only the Vault section for the requested operation.
- Treat root/recovery material, tokens, and secret payloads as sensitive; never include them in output.
- No commits; request explicit operator approval before initialization, restore, seal, or destructive changes.
