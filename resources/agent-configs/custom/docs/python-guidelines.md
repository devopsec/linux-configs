## Python - Development Best Practices

### General
- Follow PEP 8 with 120 character line limit
- Use exact version pins (`==`) for all package dependencies in `pyproject.toml`
- Use single quotes for Python strings
- Use triple double-quoted strings for docstrings
- Sort imports with `isort`
- Use f-strings for string formatting (prefer double quotes for f-strings)
- Target the project's declared `python_requires`; otherwise modern 3.11+ syntax (`X | None`, `match` only when clearer)
- Type-hint all public functions and dataclass fields; run `ruff` (or project linter) and `mypy`/`pyright` when configured
- `pathlib.Path` over `os.path`; `subprocess.run([...], check=True, text=True)` with list args, never `shell=True` on untrusted input
- `logging` (module logger) instead of `print` in libraries; `print` only for CLI user output
- Catch specific exceptions; re-raise with context (`raise ... from err`); no bare `except:` or `except Exception: pass`
- CLIs: `argparse` with `--help` text, sane defaults for bare invocation, `--dry-run`/`--yes` for mutating actions, non-zero exit on failure
- Prefer stdlib; add a dependency only when it removes substantial code, and pin it
- No mutable default args; use `dataclasses`/`TypedDict` over ad-hoc dicts for structured data

### Settings
- Use environment variables in a single `settings.py` file
- Never commit secrets to version control

### Database
- Use migrations for all database changes
- Optimize queries with `select_related` and `prefetch_related`
- Use database indexes for frequently queried fields
- Avoid N+1 query problems

### Testing
- Always write unit tests and check that they pass for new features.
- Test both positive and negative scenarios
- `pytest` style (plain asserts, fixtures, `tmp_path`); parametrize edge cases; mock only at boundaries (I/O, network, time)
- Run the narrowest selection first: `pytest path/to/test_x.py -k name -q`

---
