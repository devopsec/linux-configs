# Python analyzer roles and defaults

## Tool selection

Use the Python config at `~/.junie/custom/configs/security/python.toml` when it exists; otherwise use `assets/config.example.toml`. Defaults: PyCharm inspections when available, plus Bandit and Ruff security rules in CI. Pin selected binaries in the project lock or immutable build image. The upstream pages checked on `2026-10-28` reported Bandit `1.9.4`, Ruff `0.17.2`, and Pylint `4.1.3`; use exact pins where selected.

| Tool | Role | Scope |
|---|---|---|
| PyCharm inspections | IDE feedback | Local changed files; respect project inspection profile |
| Bandit `1.9.4` | Python security checks | Repository/package scan; use the established config |
| Ruff `0.17.2` | Fast `S` security rules | Add `S` to existing lint selection; use locked version |
| Pylint `4.1.3` | General static analysis | Optional when already used by the project |
| mypy / Pyre-Pysa / Pyright | Type and taint-adjacent checks | Select the configured checker; type-checking is not a substitute for SAST |
| Xenon | Complexity thresholds | Optional maintainability signal, not a vulnerability detector |
| OpenGrep / CodeQL | Pattern and deeper dataflow scans | Delegate to `sec-code-semgrep-scan` |
| pip-audit | Third-party dependency advisories | Delegate to `sec-python-dependency-scan` |
| Gitleaks | Credentials in Git/source | Delegate to `sec-git-secrets-scan` |

## Bandit and Ruff defaults

```toml
[tool.ruff.lint]
extend-select = ["S"]

[tool.ruff.lint.per-file-ignores]
"**/tests/**" = ["S101"]

[tool.bandit]
exclude_dirs = ["tests", ".venv"]
skips = []
```

```bash
uv run --locked bandit -r <python-source-roots> -lll -iii
uv run --locked ruff check --select S <python-source-roots>
```

Use the repository's existing tool locks/configuration. Prefer inline suppressions with rule ID and reason over global skips. Preserve non-security Ruff rules and existing per-file policy.

## Findings and safe fixes

| Finding | Safer direction |
|---|---|
| `shell=True` / `os.system` | `subprocess.run([...], check=True)`; avoid a shell |
| Dynamic SQL | Bind parameters through the DB driver/ORM |
| `pickle` on untrusted input | Use a safe format or isolated conversion |
| `yaml.load` | `yaml.safe_load` with schema validation where needed |
| `random` for tokens | `secrets` module |
| Hardcoded password/token | Secret manager or protected runtime environment |
| TLS verification disabled | Restore certificate verification and use an approved CA bundle |

## Diff-aware and full scans

Run focused checks on changed Python files for fast feedback, then a full package/repository scan on the default branch or scheduled CI. For tools without native diff support, compare a full scan against a reviewed baseline and gate only new findings; never use a PR-only scan as the permanent security record. Route cross-language patterns/dataflow, dependency CVEs, and Git secret findings to the sibling skills instead of duplicating their workflows here.