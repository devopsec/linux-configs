# Documentation update map

After a TODO ships, update the smallest honest set of docs.

| Change type | Prefer updating |
|-------------|-----------------|
| New CLI flag / subcommand | Command reference, `--help` text, README usage |
| Config key / env var | Config reference, example configs, install notes |
| HTTP/API contract | OpenAPI/ICD, error code tables, client notes |
| SIP / Kamailio behavior | Platform SIP docs, module README, rate-limit notes |
| Install / packaging | install scripts comments only if no install.md; packaging README |
| Internal only refactor | None required unless architecture docs claim old structure |
| Bug fix user-visible | Changelog or "Known issues" removal |
| Security fix | Security notes if project maintains them; never log credentials |

## Tracker vs product docs

- **Tracker** = work state (open/done).
- **Product/module docs** = lasting truth about the system.

Both must agree after implementation. If product docs would need a large rewrite, add a short accurate subsection and flag broader doc debt to the user instead of inventing a new doc tree.

## Sibling-platform monorepos

When porting a feature (e.g. platform A → platform B):

1. Diff docs as well as code.
2. Update B’s docs to the same depth as A for that feature.
3. Note intentional deltas (names, paths, ports) explicitly.
