# C3 review checklist (0.8.x)

Ordered by severity. API names follow c3c 0.8.5 — confirm against the project's compiler with
`../dev-c3-code-create/scripts/std-find.sh`.

## Contents
1. Memory and ownership
2. Errors (Optionals/excuses), cleanup
3. Undefined behaviour and integer safety
4. Pointers, strings, C interop
5. Concurrency
6. I/O and networking
7. API and type design
8. Version drift and build
9. Tests
10. Performance
11. Style and docs

## 1. Memory and ownership (blocker)

- [ ] Every allocation (`mem::new*`, `malloc`, `@clone`, `string::format(mem…)`, `.copy(mem)`,
      `file::load(mem…)`, `x.init(mem)`) has one owner and one release; `defer` right after
      acquisition, `defer (catch)` when ownership moves to the caller on success.
- [ ] No `!` rethrow between an allocation and its `defer` (leak on that path).
- [ ] Freed with the allocator that allocated it; aligned allocations with `free_aligned`;
      nothing individually freed from arenas/temp.
- [ ] **Temp memory** (`t*` functions, `tmem`, zero-init containers) never outlives its `@pool`:
      not stored in globals/fields of longer-lived objects, not returned from inside a
      `@pool` (copy to the caller's allocator first), not sent to other threads.
- [ ] Zero-initialized `List`/`HashMap`/`DString` that must live long are `init(mem)`ed (or
      `ONHEAP` globals) — otherwise they silently allocate on `tmem`.
- [ ] Containers' elements freed before `free()` of the container when they own memory;
      HashMap copies String keys (HashSet/SortedMap/TreeSet don't).
- [ ] Views (`trim`, `split` elements, `str_view`, `[a..b]`, `Reader`/`Scanner` results)
      don't outlive their source; `DString.str_view()` not used after further appends.
- [ ] Raw threads wrap their body in `@pool_init(...)` before any temp use; `Thread` storage
      outlives `create`.
- [ ] Tests run with leak tracking (no `--test-noleak` in CI/scripts).

## 2. Errors and cleanup (blocker)

- [ ] No ignored excuses: `if (catch err = x) {}`, `(void)fallible()` on writes/close of
      written files, `?? 0` that hides real failures. Each discard has a reason.
- [ ] `!!` only in tests or provably impossible cases — never on I/O, parsing, allocation
      with user-controlled sizes, network.
- [ ] Specific excuses (`excuse PARSE_FAILED, ...`), translated at module boundaries
      (`?? MY_FAULT~`), documented with `@return?`.
- [ ] Contracts used for caller bugs, Optionals for runtime conditions; untrusted input is
      validated with real checks (contracts vanish/become assumptions in `-O2+`).
- [ ] `defer` placed immediately after acquisition; `defer try`/`defer (catch)` used for
      commit/rollback semantics where needed.

## 3. Undefined behaviour and integer safety

- [ ] Index/length arithmetic can't go negative or out of range (`len - 1` on empty slices,
      `sz` underflow); `@require [n] n >= 0 && n <= buf.len` on public functions.
- [ ] Explicit casts at signed/unsigned and narrowing boundaries are *checked* (range test
      before the cast) when the value comes from input; `math::overflow_add/mul` for sizes from
      untrusted data. Signed overflow wraps silently in C3 — it is not trapped by default.
- [ ] Division/modulo/shift operands validated; `unreachable()` really unreachable.
- [ ] `@noinit` variables fully written before reads.
- [ ] Shipping configuration: safe build (`-O1`) unless profiling justifies `-O2+`; if unsafe,
      tests and fuzzing ran in safe/sanitized builds.

## 4. Pointers, strings, C interop

- [ ] `String` → `ZString`/`char*` only for NUL-terminated data (literals, `copy`, `format`);
      otherwise `zstr_tcopy()`/`zstr_copy(alloc)`.
- [ ] `extern fn` prototypes use C types (`CInt`, `CLong`, `usz` for `size_t`, `ZString`),
      correct pointer constness by contract (`@param [in]`), arrays as pointers.
- [ ] Memory crossing the boundary freed by the side that allocated it; borrowed C strings
      copied before use after the C call.
- [ ] Exported functions (`@export("name")`) use C-compatible signatures; Optionals/slices
      across the ABI are documented.
- [ ] `any` casts checked (`anycast`, `switch (a.type)`); no raw pointer casts between
      unrelated struct types without layout guarantees (`@packed`/explicit sizes).

## 5. Concurrency

- [ ] Shared state protected by `Mutex`/`@in_lock` or atomics with documented orderings;
      no lock held across blocking I/O; no self-relock (aborts in safe builds).
- [ ] Atomic counters on hot paths padded to cache lines (`@align(64)`) when shared.
- [ ] Channels closed and destroyed; worker loops exit on `CHANNEL_CLOSED`; `ThreadPool`
      `destroy()` called; thread `join` results handled.
- [ ] No temp memory or stack addresses passed to other threads.
- [ ] Verified with `--sanitize=thread` for nontrivial concurrent code.

## 6. I/O and networking

- [ ] Reads bounded (buffer sizes, `readline(..., limit)`), partial reads/writes handled
      (`io::read_all`/`write_all`, `WOULD_BLOCK` + poll), `InStream.read` 0-at-EOF semantics.
- [ ] SIGPIPE ignored (or `MSG_NOSIGNAL`) in socket servers; sockets/files closed on all paths.
- [ ] Timeouts on connects/polls; non-blocking sockets don't spin.
- [ ] Child processes: `INHERIT_ENV` decided deliberately; stdout/stderr pipes drained or
      inherited (deadlock otherwise); `destroy()` called.
- [ ] Paths from users normalized/validated (`..`, absolute paths) before file access.
- [ ] Buffered `WriteBuffer`/`File` writes flushed/closed and their errors checked.

## 7. API and type design

- [ ] Allocator-first parameters for allocating functions; `t*` variants only as convenience.
- [ ] `typedef` for IDs/units (`typedef UserId = long;`) instead of raw ints; `@constinit` only
      where literal init is desirable.
- [ ] Enums for closed sets, `constset` for C/wire values; bitstructs for flags/protocol bits.
- [ ] Functions vs methods per stdlib guideline (methods operate on a value).
- [ ] `@private`/`@local` for internals; `@public` imports only inside a library.
- [ ] Macros: `@` prefix when they take `#expr`/`@body`; contracts with `$defined` for clear
      errors; no `$expand`/`$exec` where a function would do.

## 8. Version drift and build

- [ ] No removed/deprecated syntax for the target c3c (`../dev-c3-version-migrate/scripts/scan-legacy.sh`).
- [ ] project.json keys valid for the compiler (`c3c --list-project-properties`); no
      `--trust=full` / `exec` without review; dependencies (`.c3l`) support the c3c version.
- [ ] Platform code gated with `@feat`; cross targets build (`--target ...`).

## 9. Tests

- [ ] `@test` coverage for logic and every excuse path (`test::@error`), edge cases (empty, max,
      malformed input), round-trips; deterministic (seeded randoms, temp dirs).
- [ ] Benchmarks (`@benchmark`) for claimed performance improvements.

## 10. Performance (after correctness)

- [ ] No per-iteration heap allocation in hot loops (`@pool`, arenas, `reserve`).
- [ ] Data layout: hot fields together, SoA where scanning one field, vectors for SIMD-friendly
      math; `@prefetch`/`@likely` only with measurements.
- [ ] Syscall batching (buffered streams, `poll` over many sockets).

## 11. Style and docs

- [ ] Naming per rules (PascalCase types, snake_case functions/variables, CAPS constants);
      project brace style consistent; no commented-out code.
- [ ] `<* *>` docs on public functions: purpose, `@param` annotations, ownership of returned
      memory, `@return?` faults, `@require`/`@ensure`.
- [ ] Optional: stdlib contribution style (tabs, Allman) when contributing upstream.
