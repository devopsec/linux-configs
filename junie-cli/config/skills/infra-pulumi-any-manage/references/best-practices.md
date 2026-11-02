# Pulumi Best Practices

## Async & Output Handling

Pulumi resources return `Output<T>` types, which are handled asynchronously.

### The `apply` Rule
- ❌ **Anti-pattern:** Never instantiate resources inside an `apply()` block. This prevents Pulumi from seeing the resource during `preview`.
- ✅ **Pattern:** Resources should be top-level. Use `Output` values as inputs to other resource constructors directly. Pulumi's engine handles the resolution.

### Concatenation
- ❌ **Anti-pattern:** `url = "https://" + bucket.domain_name` (if `domain_name` is an `Output`).
- ✅ **Pattern (TS):** `url = pulumi.interpolate`https://${bucket.domain_name}``
- ✅ **Pattern (Python):** `url = bucket.domain_name.apply(lambda d: f"https://{d}")` or `Output.concat("https://", bucket.domain_name)`

## Resource Naming

### Autonaming
Pulumi appends a random suffix to physical resource names to avoid collisions.
- **Logical Name:** The name used in the code (e.g., `new aws.s3.Bucket("my-bucket")`).
- **Physical Name:** The name in the cloud (e.g., `my-bucket-d7ac2b`).

**Why?** Allows zero-downtime replacements. If you change a property that requires recreation, Pulumi creates the new one (with a different random suffix) before deleting the old one.

### Deterministic Names
Only use the `name` property if:
1. An external system expects an exact name.
2. You are using a resource that doesn't support autonaming.

## Component Resources

Group related resources into a `ComponentResource`.

### Checklist for Components:
1. **Inheritance:** Extend `pulumi.ComponentResource`.
2. **Super Call:** Call `super(type, name, args, opts)` correctly.
3. **Parenting:** Pass `{ parent: this }` to all child resources to ensure they appear correctly in the tree.
4. **Register Outputs:** Call `this.registerOutputs()` at the end of the constructor.

## Secrets Management

### Marking Secrets
Use `pulumi.secret(value)` to ensure a value is encrypted in the state and masked in the CLI.

### Config
- `pulumi config set --secret myPassword password123`
- Retrieve with `config.requireSecret("myPassword")`.

### ESC (Environments, Secrets, and Configuration)
Prefer Pulumi ESC for managing secrets across stacks and projects. It allows dynamic OIDC-based secrets and centralized auditing.
