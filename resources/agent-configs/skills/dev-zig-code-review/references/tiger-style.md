# TigerStyle (opt-in)

Paraphrased from TigerBeetle's style guide
(<https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md>) and the zigcc
`zig-tiger-style` digest. Apply only when the project adopts TigerStyle or the user asks — it is
stricter than std style and some rules (snake_case functions in TigerBeetle) conflict with it.
Priority order: **safety > performance > developer experience**.

## Safety

- Simple, explicit control flow; no recursion unless provably bounded.
- Every loop and queue has a fixed upper bound; intentionally infinite loops (event loops) are
  asserted as such.
- Assertions guard programmer errors, not expected runtime errors. Target ≥ 2 assertions per
  function: arguments on entry, invariants, results.
- Pair assertions: check a property on two code paths (e.g. before write and after read).
- Assert positive *and* negative space; split compound asserts (`assert(a); assert(b);`);
  implications as `if (a) assert(b);`.
- `comptime assert` relationships between constants (`@sizeOf(Header) == 128`).
- All errors handled; none discarded.
- Explicitly sized integers (`u32`, `u64`) over `usize` where the domain allows.
- Variables declared in the smallest scope, close to use; no aliasing of the same data under
  two names.
- Large structs initialized in place through an out-pointer (`fn init(self: *T) void`) for
  pointer stability and no copies.
- Static allocation at startup where possible; no dynamic allocation after initialization in
  the steady state.
- Keep functions short (TigerBeetle hard limit: 70 lines). Push `if`s up, `for`s down; the
  parent owns state and branching, helpers compute.

## Performance

- Design-phase back-of-envelope across network, disk, memory, CPU × bandwidth, latency.
- Batch everything; separate control plane from data plane.
- Hot loops as standalone functions with primitive arguments (no `self`) so the compiler keeps
  values in registers.
- Pass options explicitly at call sites rather than relying on defaults.

## Naming and layout

- No abbreviations (except trivial loop indices); acronyms fully capitalized (`VSRState`).
- Units and qualifiers last, most significant first: `latency_ms_max`, `size_bytes_min`.
- Same-length names for paired concepts (`source`/`target`, `source_offset`/`target_offset`).
- Callbacks last in parameter lists; helper names prefixed by caller (`read_sector_callback`).
- Two or more same-typed args → a named `options` struct.
- Distinguish `index` (0-based), `count` (1-based), `size` (count × unit); name conversions.
- Division intent explicit: `@divExact`, `@divFloor`, `@divCeil` (0.17+).
- File order: `main`/most important first; struct order: fields, then types, then methods.

## Formatting and comments

- `zig fmt`; hard limit 100 columns (use trailing commas to let `zig fmt` wrap).
- Braces on every multi-line `if`.
- Comments are sentences explaining *why*; tests start with a comment describing goal and method.

## Dependencies and tooling

- Zero dependencies beyond the Zig toolchain where feasible; scripts in Zig (`scripts/*.zig`)
  over shell for cross-platform tooling.

## Review checklist (TigerStyle additions)

- [ ] Bounded loops/queues; infinite loops asserted.
- [ ] Assertion density: entry arguments, invariants, results; paired where data crosses a boundary.
- [ ] No error discarded; no `catch unreachable` without proof.
- [ ] Names carry units/qualifiers; no abbreviations; options structs for same-typed params.
- [ ] Functions ≤ ~70 lines; branching centralized in the parent.
- [ ] Lines ≤ 100 columns; `zig fmt` clean.
