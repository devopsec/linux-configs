# Claude specifics — dev-c3-version-migrate

- Run `scan-legacy.sh -q` first and share the summary before editing; large trees: port one
  module directory per turn and rebuild between them.
- Edit hit by hit with Edit (renames like `.sizeof` → `::size` are safe to batch per file; type
  and signedness changes are not — they ripple into call sites).
- To compare old and new stdlib APIs, shallow-clone the two c3c tags (read-only data) and diff
  the relevant `lib/std` files instead of guessing; delegate wide sweeps to an Explore agent.
- Downloading another c3c, updating vendored libraries or CI pins needs the user's approval.
  Don't commit.
