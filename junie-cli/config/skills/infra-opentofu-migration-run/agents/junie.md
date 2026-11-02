# Junie specifics — OpenTofu migration

- Treat migration as plan-only until the user approves a cutover.
- Preserve state backups and provider lockfiles; never run both runtimes against one state concurrently.
- Report exact CLI/provider versions and any plan delta from the Terraform baseline.
