# Junie specifics — gfx-iconify-icon-manage

- Run `iconify` via `npx iconify-cli@latest` when it is not on `$PATH`; the network is needed only for search and download.
- Restrict `search` output with `-p` and `| head`; write results only into the configured `out_dir` inside the repo.
- Never commit; report the downloaded icon IDs and files for human review.
