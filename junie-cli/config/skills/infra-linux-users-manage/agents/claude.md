# Claude Specifics for Infra Linux Users Manage

## Context & Tuning
- Follow the least-privilege workflow and inspect the active NSS/PAM identity source.
- Preserve unrelated groups and user data when recommending account changes.

## Instructions Overrides
- Ask before destructive deprovisioning or granting additional sudo privileges.
- Never quote credentials, password hashes, private keys, or sensitive user records.
