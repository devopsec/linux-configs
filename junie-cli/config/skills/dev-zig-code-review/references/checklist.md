# Zig review checklist

Ordered by severity. Each item: what to look for → why it matters → the fix to suggest.
Version-specific API names follow 0.17; confirm against the project's pinned series.

## Contents
1. Memory and ownership
2. Error handling
3. Illegal behavior and integer safety
4. Pointers, casts, and layout
5. Concurrency and std.Io
6. I/O correctness
7. API design
8. Version drift and build hygiene
9. Tests
10. Performance
11. Style and docs

## 1. Memory and ownership (blocker)

- [ ] Every `alloc/create/dupe/print/toOwnedSlice/readFileAlloc` result has exactly one owner and
      one free. `defer` right after acquisition when freed locally; `errdefer` when ownership
      leaves on success. A `try` between allocation and `errdefer` leaks on that error path.
- [ ] Multi-step constructors: each acquired resource has its own `errdefer` in order; `deinit`
      releases in reverse and leaves `self.* = undefined`.
- [ ] Freed with the same allocator that allocated; nothing freed from an arena individually; no
      double free across `deinit` + `toOwnedSlice`.
- [ ] No pointers/slices into an `ArrayList`/`HashMap` kept across an operation that can grow it
      (`append`, `put`, `ensureCapacity`). Same for slices from `Reader.take*`/`peek*` after the
      next read.
- [ ] No returned pointer to a stack local or by-value parameter; no self-referential struct
      returned by value (internal pointer dangles after the copy).
- [ ] HashMap string keys outlive the map (dupe them if the source buffer is temporary) and are
      freed on removal/deinit.
- [ ] Tests use `std.testing.allocator`; allocation-heavy code has `checkAllAllocationFailures`.

## 2. Error handling (blocker)

- [ ] No `catch unreachable` on anything that can fail at runtime (allocation, I/O, parsing,
      user input). Allowed only with a comment proving impossibility.
- [ ] No swallowed errors (`catch {}`, `catch |_| {}`, `catch return`) without a comment and a
      log; fallible cleanup in `defer` is handled or explicitly ignored with reasoning.
- [ ] Error sets: public APIs declare or document them; no `anyerror` leaking into APIs; error
      names are specific (`error.InvalidHeader`, not `error.Failed`).
- [ ] `error.Canceled` (0.16+) propagated, never swallowed — otherwise `Group.cancel` hangs.
- [ ] Errors vs. assertions: invalid *input* → error; violated *invariant* → `assert`/panic.

## 3. Illegal behavior and integer safety (blocker in safe code paths)

- [ ] `@intCast` / `@truncate` / `@intFromFloat` / `@fromBackingInt` on untrusted values are
      range-checked first (`std.math.cast`, `std.enums.fromInt`).
- [ ] `len - 1`, `a - b` on unsigned values guarded against underflow; `+`/`*` on sizes use
      `std.math.add/mul` when inputs are external.
- [ ] Division/modulo by runtime values checked for zero; `@divExact` only when exactness is
      guaranteed.
- [ ] `.?` and union payload access only where the value is proven non-null / the tag active.
- [ ] `undefined` never read; partially initialized structs not observed.
- [ ] `@setRuntimeSafety(false)` / `ReleaseFast` justified by a benchmark, scoped to the hot
      loop, and covered by tests in Debug.

## 4. Pointers, casts, and layout

- [ ] `@ptrCast` between types of compatible size and alignment; `@alignCast` present when
      alignment increases and actually guaranteed.
- [ ] `@bitCast` (0.17): not on `extern` types; array/vector casts reviewed for endianness.
- [ ] Data crossing an ABI or written to disk/network uses `extern struct` / `packed struct` with
      explicit integer widths and documented endianness (`std.mem.writeInt(.little)`), never a
      plain `struct`.
- [ ] `[*c]T` from C converted to precise pointer types at the boundary; sentinel strings
      (`[:0]u8`) used where C expects NUL termination.
- [ ] `@constCast` never used to write to genuinely const memory (string literals, comptime data).

## 5. Concurrency and std.Io (0.16+)

- [ ] Shared mutable state guarded by `std.Io.Mutex`/`RwLock` or atomics; lock held for the
      minimum span; no lock held across `io` calls that may block indefinitely.
- [ ] `io` and allocators passed in, not created in library code; no `std.Io.Threaded` per call.
- [ ] `io.async` results always `await`ed or `cancel`ed; groups `cancel`ed on error paths
      (`defer group.cancel(io)`).
- [ ] `io.concurrent` used where tasks must make progress simultaneously (producer/consumer);
      `async` may run inline and deadlock such pairs.
- [ ] No libc/pthreads/`std.posix.system` calls duplicating what `std.Io` provides (breaks
      cancelation and evented backends).
- [ ] Atomics use the weakest correct ordering with a comment; no `.unordered` on shared flags.

## 6. I/O correctness

- [ ] Every buffered `Writer` is `flush`ed before it goes out of scope or output is expected.
- [ ] Reader buffers are large enough for the longest delimited record (`error.StreamTooLong`
      handled); `takeDelimiter` EOF (`null`) handled.
- [ ] Reads bounded: `readFileAlloc(..., .limited(n))` / `allocRemaining(gpa, .limited(n))` with a
      sane `n` for untrusted input — never `.unlimited` on network data.
- [ ] Files/sockets/dirs closed on every path (`defer x.close(io)`).
- [ ] Paths from users not joined into privileged locations without validation (`..`, absolute
      paths, symlinks — consider `resolve_beneath` options).

## 7. API design

- [ ] Allocator first (or after `self`), `io` next; options structs for 2+ same-typed params.
- [ ] Ownership of returned memory documented in the doc comment ("caller owns", "valid until").
- [ ] Unmanaged containers in public structs; `init`/`deinit` pairs; `.empty` decl literal where
      zero-init is meaningful.
- [ ] Tagged unions instead of structs with mutually exclusive optional fields; distinct ID types
      (`enum(u32) { _ }`) instead of raw integers.
- [ ] `anytype` parameters document the expected interface and fail with `@compileError` messages.
- [ ] `pub` surface minimal; internals not exported just for tests (tests live in the same file).

## 8. Version drift and build hygiene

- [ ] No APIs removed or deprecated for the pinned series (`../dev-zig-version-migrate/scripts/scan-legacy.sh`).
- [ ] `build.zig` uses `standardTargetOptions`/`standardOptimizeOption`, `root_module`, Module
      methods for C/link settings; no `b.args` (0.17); no reading the filesystem at configure time.
- [ ] `build.zig.zon`: `minimum_zig_version` set; dependencies pinned to immutable refs with
      hashes from `zig fetch`; `.paths` lists only what the package needs.
- [ ] `.gitignore` covers `.zig-cache/`, `zig-out/`, `zig-pkg/`.

## 9. Tests

- [ ] New logic has `test` blocks next to it; edge cases (empty, max, invalid) and error paths
      (`expectError`) covered.
- [ ] Tests are deterministic (seeded PRNG, `testing.tmpDir`, no wall-clock sleeps, no network).
- [ ] Parsers/decoders have a fuzz test; regression inputs captured as unit tests.
- [ ] Test files reachable from the test root (`refAllDecls` / `_ = @import(...)`).

## 10. Performance (only after correctness)

- [ ] No allocation in hot loops (arena, pool, or preallocated capacity with `*AssumeCapacity`).
- [ ] Large values passed by `*const T`; hot structs small; struct-of-arrays (`MultiArrayList`)
      for scans over one field.
- [ ] `comptime` used for real specialization, not to unroll huge loops (`@setEvalBranchQuota`
      warnings are a smell).
- [ ] Batching for syscalls/I/O (`writeVecAll`, `sendFileAll`, buffered writers).

## 11. Style and docs

- [ ] `zig fmt` clean; naming per std style (TitleCase types, camelCase functions, snake_case
      variables); no redundant names (`json.JsonParser` → `json.Parser`).
- [ ] `///` doc comments on every `pub` decl; `//!` module doc on files.
- [ ] Comments explain *why*; no commented-out code; TODOs reference an issue.
- [ ] Project-specific style (e.g. TigerStyle — `tiger-style.md`) applied only if the project
      adopts it or the user asks.
