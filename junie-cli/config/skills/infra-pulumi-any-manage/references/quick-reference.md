# Quick Reference: Pulumi vs Terraform

## Comparison Table

| Feature | Pulumi | Terraform / OpenTofu |
|---------|--------|----------------------|
| **Language** | General-purpose (TS, Python, Go, etc.) + YAML | HCL (DSL) |
| **State Storage** | Pulumi Cloud (default), S3, GCS, Azure Blob | Local, S3 + DynamoDB, HCP Terraform |
| **Abstractions** | Classes, Functions, ComponentResources | Modules |
| **Secrets** | Built-in encryption, Pulumi ESC | Variable masking, external managers |
| **Logic** | Native loops, conditionals, libraries | `count`, `for_each`, limited functions |
| **Testing** | Standard language frameworks (pytest, mocha) | `terraform test`, Terratest (Go) |
| **Programmatic** | Automation API (First-class SDK) | Limited via Go packages or CLI wrapping |
| **Versioning** | Standard package managers (npm, pip) | Provider/Module versions in HCL |

## CLI Cheat Sheet

| Command | Action |
|---------|--------|
| `pulumi new` | Create a new project from a template |
| `pulumi login` | Authenticate with the backend |
| `pulumi stack ls` | List stacks in the current project |
| `pulumi stack select` | Set the active stack |
| `pulumi config` | Manage stack configuration and secrets |
| `pulumi preview` | Show a plan of infrastructure changes |
| `pulumi up` | Create or update infrastructure |
| `pulumi refresh` | Sync state with real-world resources |
| `pulumi destroy` | Tear down all resources in the stack |
| `pulumi stack output` | View exported stack outputs |
| `pulumi import` | Bring existing resources into Pulumi management |
| `pulumi convert` | Convert HCL or ARM templates to Pulumi |

## Critical Differences to Remember

1. **Imperative vs. Declarative Execution:**
   - Terraform builds a graph of everything first.
   - Pulumi executes your program. Resources are registered as the code runs.
   - **Agent Warning:** You cannot use an `Output` value as a normal string/integer in your code (e.g., in an `if` statement) because it's only known during deployment. You must use `.apply()` or `pulumi.interpolate`.

2. **Autonaming:**
   - Terraform usually requires you to provide a unique name.
   - Pulumi generates a unique name by default. This avoids name collisions but can be confusing if you expect exact names.

3. **Refactoring:**
   - Moving a resource in Terraform requires `moved` blocks or `state mv`.
   - In Pulumi, you can often just move the code, but you may need to use `aliases` in the `ResourceOptions` to tell Pulumi "this new resource is actually the old one".

4. **Automation API:**
   - You can write a Python script that imports `pulumi.automation` to manage stacks. This is much more powerful than shell scripts calling `terraform`.
