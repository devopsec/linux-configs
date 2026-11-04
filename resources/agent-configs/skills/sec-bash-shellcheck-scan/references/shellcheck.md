# ShellCheck

ShellCheck `v0.11.0` was the stable release checked on `2026-10-28`. Pin the package/container to that exact release or immutable digest and verify its source/checksum. Use the repository's existing `.shellcheckrc` when present.

## Discover and run

Include tracked shell files and extensionless scripts identified by shebang:

```bash
git ls-files -z | xargs -0 file --mime-type \
  | awk -F': ' '$2 == "text/x-shellscript" {print $1}' > /tmp/shell-files.txt
git ls-files -z -- '*.sh' '*.bash' >> /tmp/shell-files.txt
sort -zu /tmp/shell-files.txt | xargs -0 -r shellcheck -S warning -f gcc
```

Use the established gate (`-S error` or `-S warning`) rather than silently changing it. JSON output can be saved in a protected temp directory:

```bash
shellcheck -f json1 path/to/script.sh > /tmp/shellcheck.json
```

## Security-relevant checks

| Check | Risk | Preferred fix |
|---|---|---|
| SC2086 / SC2048 | Unquoted splitting and glob expansion | Quote values or use arrays |
| SC2046 | Command substitution splitting | Quote the result or use `mapfile` |
| SC2155 | Assignment masks command exit status | Declare and assign separately |
| SC2164 | Failed `cd` continues in the wrong directory | Check the status or exit |
| SC2115 | Empty variable can broaden recursive deletion | Require a non-empty variable before use |
| SC2294 | `eval` risks code injection | Use arrays and direct argument passing |

Review dangerous constructs manually: `eval`, downloaded script execution, unvalidated privileged arguments, secret values in argv, and temporary files with permissive modes.

## Changed files and full scan

Run a quick check against changed shell paths for PR feedback, then scan all tracked/shebang-detected scripts for the merge gate. ShellCheck does not provide a semantic diff baseline; do not treat a changed-files run as proof the repository is clean. Ratchet warnings in batches while preserving the existing error threshold.