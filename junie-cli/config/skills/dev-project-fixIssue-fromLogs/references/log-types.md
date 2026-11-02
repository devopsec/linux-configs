# Log types — signatures and first commands

## CMake / CLion

**Paths:** `build/<preset>/CMakeFiles/clion-Build-*.log`, `CMakeCache.txt`, `CMakeError.log`, `CMakeOutput.log`

**Signatures:**
- `Could not find` / `CONFIG` package not found → `CMAKE_PREFIX_PATH`, Conan/vcpkg integrate
- `Unknown CMake command` → missing `include` / wrong cmake_minimum
- Compiler id / sysroot failures → toolchain file

**Approach:**
1. Jump to the **last** `CMake Error` / `FAILED:` block unless asked otherwise.
2. Map to `CMakeLists.txt` or `*.cmake` at the cited line.
3. Prefer fixing find modules / package paths over vendoring.

## Ninja / generated sources

**Signatures:** `multiple rules generate <file>`, Flex/Bison double rules, stale `lex.yy.c`

**Approach:**
- Find duplicate `add_custom_command` / two targets owning one output.
- Clean only the conflicting generated files if safe; avoid full `rm -rf build` as first move.

## Compiler / linker

**Approach:**
- First `error:` wins; ignore following cascades.
- `undefined reference` → missing lib, wrong link order, `#ifdef` mismatch.
- Keep compile_commands / single-file rebuild when possible.

## Tests

- Re-run single case with the project’s normal filter flag.
- Distinguish fixture/env fail from assertion fail.

## journald / systemd

```bash
journalctl -u <unit> -b --no-pager -n 200
systemctl status <unit> --no-pager
```

Prefer unit logs over entire system boot unless diagnosing boot.

## Application / HTTP

- Grab request id / correlation id if present.
- 502/504 → upstream health; 4xx → client/contract; 5xx → app stack.

## SIP / Kamailio

- `ERROR: <module> [file:line]`
- Check `kamcmd`/`kamctl` only if already part of project ops docs.
- Deep module/config work → `dev-kamailio-platform-manage`.

## Docker / CI

- Failed step name + exit code.
- Cache poisoning: lockfiles, base image digests.
- Reproduce the step locally with the same env vars when feasible.

## Toolchain (Node/Python/etc.)

- `pnpm` + Volta: PATH shim vs global mismatch.
- Python: venv not active, wrong interpreter in IDE.
