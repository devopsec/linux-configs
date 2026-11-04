# Fix playbook

## Ranking errors

1. **Configuration missing** (tool not found, wrong generator) — blocks everything.
2. **Dependency / path** (package not found).
3. **Code compile error** at earliest file in the dependency order.
4. **Link errors** after compile is clean.
5. **Runtime / test** after build is clean.
6. **Warnings** only if `-Werror` or user asked.

When the user says "last error only", take the final fatal signature even if earlier warnings exist.

## Extraction hygiene

```bash
# Example: keep evidence out of chat
rg -n "error:|FAILED|CMake Error|ninja: error" "$LOG" | tail -n 80 > /tmp/log-errors.txt
```

Summarize from the extract; cite file:line.

## Verification ladder

1. Re-run the exact failing command.
2. If too heavy, run the single target/test that failed.
3. Only widen (full suite) for cross-cutting changes.

## Anti-thrash

| Bad | Good |
|-----|------|
| Delete entire `build/` first | Delete specific stale generated file |
| Edit vendored third_party blindly | Fix consumer CMake / pins |
| Silence error with broad `#pragma` / `-Wno-error` | Fix root cause |
| Multiple unrelated fixes in one shot | One hypothesis → one fix → re-run |
| Paste 2k-line log into chat | Extract top signatures to `/tmp` |

## Stop conditions

- Ask the user if the fix requires secret credentials, destructive prod changes, or upgrading a major toolchain without a pin strategy.
- If two equally likely root causes remain after one falsification attempt, present both briefly and recommend one.
