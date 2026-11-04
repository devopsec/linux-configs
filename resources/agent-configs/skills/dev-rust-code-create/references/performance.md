# Performance: measure, then optimize

No optimization without a benchmark or profile that shows the hotspot and a before/after
number. Correctness and clarity first; keep optimized code tested against a simple reference
implementation (property test: `fast(x) == simple(x)`).

## Measure

- **Benchmarks:** `criterion` (statistical, HTML reports) or `divan` (lighter, allocation
  counters) in `benches/` with `[[bench]] name = "x" harness = false`. `#[bench]` is unstable
  and destabilized *(1.88)*. Use `std::hint::black_box` on inputs and outputs.
- Benchmark in `--release` with the profile you ship (LTO/codegen-units matter); on a quiet
  machine; compare against a saved baseline (`cargo bench -- --save-baseline before`).
- **Profiling:** build with `[profile.profiling]` (`inherits = "release"`, `debug = true`),
  then `perf record --call-graph dwarf target/profiling/app` + `perf report`,
  `samply record` (Firefox profiler UI), or `cargo flamegraph` if installed. Ask before
  changing `kernel.perf_event_paranoid`.
- Allocation profiling: `dhat` crate (heap profiler as a global allocator in a test/bench),
  `heaptrack`, or `bytehound`.
- Assembly: `cargo asm` (cargo-show-asm) or Compiler Explorer to confirm vectorization and
  bounds-check elimination.
- `cargo build --timings` and `cargo llvm-lines` for compile-time bloat.

## Allocation and memory

- Reuse buffers: `Vec::clear()` keeps capacity; pass `&mut Vec<T>` / `&mut String` into hot
  functions instead of returning new ones. `with_capacity` when the size is known.
- Avoid `clone()`/`to_string()`/`format!` in hot loops; `write!` into a reused `String`;
  `itoa`/`ryu` or `NumBuffer` *(1.98)* for number formatting.
- Small collections: `smallvec`/`arrayvec`/`tinyvec`; small strings: `compact_str`.
- Many short-lived allocations with one lifetime: arena (`bumpalo`, `typed-arena`) or slab
  (`slab`) with indices.
- Global allocator for allocation-heavy multi-threaded services: `mimalloc` or
  `tikv-jemallocator` — benchmark, don't assume.
- Hash maps: default SipHash is DoS-resistant; for trusted keys use `rustc-hash` (FxHash),
  `ahash`, or `foldhash`. `HashMap::with_capacity_and_hasher`.
- `Box<[T]>`/`Arc<str>` for immutable data shrinks structs; check type sizes with
  `size_of::<T>()` and keep hot enums small (box large variants).

## CPU and data layout

- Iterate contiguous memory; struct-of-arrays for hot fields scanned in bulk; avoid
  `Vec<Box<T>>`/linked lists/pointer chasing.
- Bounds checks: iterators, `chunks_exact`, `as_chunks` *(1.88)*, or an `assert!(i < len)`
  before a loop let LLVM remove them; `get_unchecked` only with a SAFETY argument and a
  measured win.
- Branches: `std::hint::cold_path()` *(1.95)*, `#[cold]` on error paths,
  `hint::select_unpredictable` *(1.88)* for data-dependent selects, `likely`-style
  restructuring (early returns for the rare case).
- Inlining: `#[inline]` on small cross-crate functions in libraries (generic fns are already
  inlinable); `#[inline(always)]` only with evidence.
- Dynamic dispatch in hot loops → generics or enum dispatch.

## SIMD and target features

- Write auto-vectorizable loops first (fixed-width chunks, no early exits, `f32` lanes) and
  check the asm.
- Portable SIMD (`std::simd`) is nightly-only; stable options: `std::arch` intrinsics,
  the `wide` or `pulp` crates, `multiversion` for function multiversioning.
- Runtime dispatch: `if is_x86_feature_detected!("avx2") { unsafe { kernel_avx2(x) } }` with
  `#[target_feature(enable = "avx2")] fn kernel_avx2` *(safe fn since 1.86)*.
- `-C target-cpu=native` only for binaries that run where they are built.

## Parallelism

- `rayon` for data parallelism (`par_iter`, `par_sort_unstable`, `join`); tune chunk sizes
  (`with_min_len`) so per-task work is ≥ ~10µs.
- Avoid shared counters on hot paths (per-thread accumulation + reduce); pad per-thread state
  to cache lines.

## Release profile checklist

`lto = "thin"|"fat"`, `codegen-units = 1`, `panic = "abort"` (if no `catch_unwind`), PGO via
`cargo pgo` for the last 10–20 % (if installed). Re-measure after each change; keep the
ones that pay.
