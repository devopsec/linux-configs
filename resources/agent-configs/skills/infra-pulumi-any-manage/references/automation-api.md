# CI/CD & Automation API

## Automation API

A programmatic SDK for driving Pulumi. It allows you to run Pulumi operations (`preview`, `up`, `destroy`) from within your application code.

### When to use:
- Building a self-service developer portal.
- Complex multi-stack orchestrations.
- Running Pulumi inside an API or CLI tool.
- Dynamic environment creation for PRs or tests.

### Implementation Pattern:
1. **LocalWorkspace:** Point to a Pulumi project on disk.
2. **Inline Program:** Define the Pulumi program as a function within your code.
3. **Select Stack:** Create or select an existing stack.
4. **Run Command:** Call `stack.up({ onOutput: console.log })`.

## CI/CD Integration

### Best Practices for CI:
1. **Non-Interactive:** Always use `--yes` or the Automation API.
2. **Commit Lockfile:** Ensure `Pulumi.yaml` and language-specific lockfiles (`package-lock.json`, `requirements.txt`, `uv.lock`) are committed.
3. **PR Previews:** Run `pulumi preview` on every pull request.
4. **Deployment Triggers:** Trigger `pulumi up` on merge to `main` for specific environments.
5. **Secrets in CI:** Use OIDC (AWS/GCP/Azure) via Pulumi ESC or GitHub Actions secrets.

### GitHub Actions Example:
```yaml
- name: Pulumi Preview
  uses: pulumi/actions@v5
  with:
    command: preview
    stack-name: dev
  env:
    PULUMI_ACCESS_TOKEN: ${{ secrets.PULUMI_ACCESS_TOKEN }}
```

## Rollback Strategy

1. **VCS Rollback:** Revert the code change in Git and re-deploy.
2. **State Import:** If a manual fix is needed, use `pulumi stack export/import`.
3. **Aliases:** Use `aliases` in resource options to safely rename resources without destroying them.
