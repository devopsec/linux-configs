# State & Backend Management

## Backends

Pulumi supports multiple backends for storing stack state.

### 1. Pulumi Cloud (Managed)
- **Default:** Encrypted, history, locking, RBAC, and web UI.
- **Login:** `pulumi login`.

### 2. Self-Managed (Cloud Storage)
- **Format:** `s3://<bucket>`, `gs://<bucket>`, `azblob://<container>`.
- **Note:** No built-in locking (needs native cloud locks), no history, no UI.
- **Login:** `pulumi login s3://my-bucket`.

### 3. Local
- **Format:** `file://~`.
- **Usage:** Only for local development/testing.

## Stacks

A **Stack** is an isolated, deployable instance of a Pulumi project.

- `pulumi stack ls`: List stacks.
- `pulumi stack select <name>`: Switch stack.
- `pulumi stack output`: View exported variables.

## State Operations

### Locking
- If a stack is locked, verify if another process is running.
- **Force Unlock:** `pulumi stack unlock --force-cancel` (Use with extreme caution).

### Drift & Refresh
- `pulumi refresh`: Compares current state against real cloud resources and updates the state file. Does NOT change infrastructure.
- Always run `refresh` if manual changes were made to resources.

### Manual State Edits
- `pulumi stack export > state.json`: Export state to JSON.
- `pulumi stack import --file state.json`: Import modified state.
- **Warning:** Direct state manipulation is high-risk. Prefer `pulumi import` or `aliases`.

## Pulumi ESC (Environments, Secrets, and Configuration)

ESC is a centralized way to manage configuration and secrets.

- **Environments:** Hierarchical YAML-based configuration.
- **Inheritance:** Environments can import other environments.
- **Dynamic Secrets:** Can generate OIDC tokens for AWS/GCP/Azure on-the-fly.
- **Usage in CLI:** `esc run <env> -- <command>` (e.g., `esc run dev -- pulumi up`).
