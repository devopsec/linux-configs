# Outdated documentation heuristics

## Automated-ish checks

```bash
# broken relative links (example approach)
rg -n '\[[^\]]+\]\(([^)]+)\)' README.md docs documentation | head
# path existence checked per match

# commands mentioned vs scripts/
rg -n '`(\./[^`]+)`' README.md
```

## Claim categories

| Category | Verify via |
|----------|------------|
| Install steps | manifest + try dry-run |
| CLI flags | `--help`, source argparse |
| Config keys | example configs + schema |
| Architecture | main entrypoints still match diagram |
| Supported versions | CI matrix, `.tool-versions`, go.mod |
| Feature lists | code paths or feature flags |

## Severity

1. **Wrong destructive command** — fix immediately
2. **Broken path / 404 link** — fix in same pass
3. **Version drift** — fix or date-stamp
4. **Tone/structure** — only if user asked organize

## False positives

- Docs for alternate platforms in a monorepo (label per platform)
- Future work sections that are intentionally aspirational — retitle to "Planned"
