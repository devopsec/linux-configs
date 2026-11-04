---
name: "dev-project-fixIssue-fromLogs"
description: "Diagnose and fix issues from logs of many kinds: CMake/CLion/Ninja build logs, compiler output, test runners, application logs, journald/syslog, nginx/HTTP, SIP/Kamailio, Docker/CI, and crash traces. Use when asked to fix build errors, parse a log file, triage condensed errors, act as system doctor, or resolve failures from a given log path."
---

# Fix issues from logs

Log-first debugging: **read → rank root cause → minimal fix → verify**, without thrashing unrelated trees.

## Triggers

- Paths like `build/**/CMakeFiles/clion-*-log.txt`, `*.log`, `condensed-errors*`, CI artifacts
- Phrases: "fix the build errors", "fix the last error in the cmake log", "triage these logs", "system issues from logs"
- Paste of stack traces, ninja errors, journalctl output

## Log-type routing

| Kind | Signals | First moves |
|------|---------|-------------|
| **CMake / CLion** | `clion-Build`, `CMake Error`, `CMAKE_PREFIX_PATH`, Conan | Tail last failing target; see [references/log-types.md](references/log-types.md#cmake-clion) |
| **Ninja / Make** | `multiple rules generate`, `ninja: error`, missing `.o` | Identify duplicate outputs / generated sources |
| **Compiler** | `error:`, `undefined reference`, fatal warnings-as-errors | Open first **error** (not first warning) file:line |
| **Test runner** | pytest/jest/ctest/go test FAIL | Reproduce single test; fix code or fixture |
| **Application** | app log levels, request ids | Correlate timestamp → code path |
| **journald / syslog** | `journalctl`, unit failures | Unit status + last meaningful stack |
| **HTTP / proxy** | nginx/caddy 5xx, upstream | Upstream vs client; config vs app |
| **SIP / Kamailio** | `kamailio`, `ERROR:`, modparam | Module + route block; see kamailio skill if deep |
| **Docker / CI** | job log, exit code, cache miss | Isolate step; local repro |
| **Package / toolchain** | pnpm/volta/npm, pip, apt | Pin/path issues before code changes |
| **Core dump / sanitizer** | ASan/UBSan/segfault | Symbolize; fix memory/race at frame 0–3 |

Load [references/log-types.md](references/log-types.md) only for the matching kind. Load [references/fix-playbook.md](references/fix-playbook.md) for the generic loop and anti-thrash rules.

## Workflow

1. **Acquire logs**
   - Prefer user-supplied path; else discover latest relevant log under `build/`, `logs/`, `/tmp`, CI download dir.
   - For huge files: tail/grep errors first; do not dump entire logs into chat (`> /tmp/...` extractions).

2. **Normalize & rank**
   - Extract distinct error signatures (dedupe repeats).
   - Rank: **root cause** > cascading failures. Fix the earliest causal error unless the user named a specific one ("last error only").
   - Record: error text, file:line if any, component (build system vs code vs env).

3. **Hypothesize (1–3 max)**
   - State the leading hypothesis and the cheapest check that would falsify it.

4. **Fix minimally**
   - Prefer project code/config over vendored trees.
   - Avoid mass-reformat, drive-by refactors, or deleting build caches unless required and explained.
   - If env/tooling: document the exact command/version pin.

5. **Verify**
   - Re-run the failing command or a focused subset.
   - Confirm the original signature is gone; scan for the next new top error only if still failing.

6. **Report**
   - Root cause, change made, verification command, residual risks / next errors if any.

## Discipline

- **One root cause per iteration** when logs show cascades.
- **Do not** reread the entire log after a fix — re-run and compare.
- **Do not** commit.
- Secrets in logs: never echo tokens/keys back; redact in summaries.

## Related skills

- Kamailio-domain runtime logs → also consider `dev-kamailio-platform-manage`
- Bash script failures in project scripts → `dev-bash-script-review`
- Terraform plan/apply errors → `infra-terraform-any-manage`

## References

- [references/log-types.md](references/log-types.md) — per-ecosystem signatures and commands
- [references/fix-playbook.md](references/fix-playbook.md) — ranking, verification, anti-patterns
