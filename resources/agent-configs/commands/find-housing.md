---
description: "Search Craigslist apartment rentals without the LLM agent — city, max rent, bedrooms/bathrooms, free-text query, optional posting details"
allowPromptArgument: true
argument-hint: "--city CITY [--max-rent N] [--min-bedrooms N] [--query TEXT] [...]"
---

EXECUTE IMMEDIATELY — one shell call. No planning, repo exploration or guideline loading.

```bash
python3 {{agent_home}}/custom/scripts/find-housing/find_housing.py --format json {{args}}
```

- Bare `/find-housing` → script prints usage and exits 2 unless `city` is set in `~/.config/find_housing.cfg`. If it exits 2 (usage error, e.g. natural-language input): run `python3 {{agent_home}}/custom/scripts/find-housing/find_housing.py -h`, map the request onto real flags using the table below, echo the resolved command, run once more.
- The body already passes `--format json` (the script's direct default is `table`). The arguments are appended after it, so a user's `--format table` wins (argparse: last value wins). Pass the arguments through **unchanged** as argv. Works the same from any agent (no agent-specific state).
- Shell metacharacters in the arguments are interpreted by bash. Quote multi-word values, and avoid `&`, `;`, `|` in `--query` (e.g. write `dogs and cats` rather than `dogs & cats`).
- `--city` is required unless `city` is set in `~/.config/find_housing.cfg`. Unknown cities fall back to the name with spaces removed. Use quotes for multi-word values, e.g. `--query "dog friendly"`.
- Defaults come from `~/.config/find_housing.cfg` (optional, section `[find_housing]`). Precedence: CLI flag > config file > built-in default. The body's `--format json` overrides a config `format = table`; a user `--format table` overrides both. Use `--no-details` to override a config `details = yes`. Config values `city`/`query`/`format` may be quoted; inline comments need ` #`/` ;` after whitespace. A config min/max bound that conflicts with the opposite CLI bound exits 2 naming both. Config errors exit 2 with the file path and key on stderr.
- Summarize the JSON in chat (rent, beds/baths, location, URL). Bulky output → `/tmp/find-housing-*.json`.

**Intent → argv**

| User wants | argv |
|------------|------|
| apartments in city X under R | `--city X --max-rent R --format json` |
| at least N bedrooms | `--city X --min-bedrooms N --format json` |
| between N and M bedrooms | `--city X --min-bedrooms N --max-bedrooms M --format json` |
| bathroom range | `--min-bathrooms A --max-bathrooms B` (add to the above) |
| free-text match (pets, parking, …) | `--query "dog friendly"` (quote multi-word text) |
| full posting text for each result | add `--details` (one extra request per listing) |
| more or fewer results | `--max-listings N` (default 10) |
| human-readable table in chat | `--format table` |

**Preconditions / side effects**

- Network: one Craigslist search request per run, plus one posting request per listing only with `--details` (capped by `--max-listings`). Read-only; nothing is written.
- Requires `uv` on PATH for the first run: the script's inline PEP 723 deps (aiohttp, beautifulsoup4) are resolved on demand when the search path runs.
- Exit codes: 0 success (including zero results), 2 argument error, 1 network, parse, or dependency-resolution failure (message on stderr, empty stdout). A uv dependency failure is reported as 1, never 2.

**Next steps**

- Offer to re-run with `--details` for a specific listing, or to narrow with `--max-rent` / `--query`.

Examples (each line is valid argv after `/find-housing`):

```text
--city "san francisco" --max-rent 3000 --min-bedrooms 1 --format json
--city "san francisco" --max-rent 3000 --query "dog friendly" --max-listings 5 --format json
--city austin --min-bedrooms 2 --max-bedrooms 3 --min-bathrooms 1 --details --format json
--city "new york" --max-listings 20 --format table
```
