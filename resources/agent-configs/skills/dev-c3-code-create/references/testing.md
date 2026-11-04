# Testing, debugging, common errors (0.8.5)

## Tests

```c3
module myapp::parser;
import std::core::test;          // test::eq etc. (std::core is implicit; import for clarity)

fn void test_parse_port() @test
{
    test::eq(parse_port("80")!!, 80);
    test::@error(parse_port("x"), PARSE_FAILED);   // expects that excuse
    test::@error(parse_port(""));                   // any excuse
    test::ne(1, 2);  test::lt(1, 2);  test::le(2, 2);  test::gt(3, 2);  test::ge(3, 3);
    test::eq_approx(1.0 / 3.0, 0.333, places: 3);
    test::@check(len > 0, "len was %d", len);
    assert(ok, "plain asserts work too");
}

module myapp::parser @test;      // a whole section of test-only code
fn void test_split() { ... }     // every fn in an @test section is a test
```

- Run: `c3c test [target]` (project: `sources` + `test-sources`), `c3c compile-test f.c3`
  (files). Filter: `--test-filter port`; see output: `--test-show-output`; quieter:
  `--test-quiet`; break into debugger on failure: `--test-breakpoint`.
- **Leak detection is on by default**: each test runs under a `TrackingAllocator` inside a
  `@pool`; leaks fail the test (`--test-noleak` disables — fix the leak instead).
- `@test` functions take no arguments and return `void` (no Optional; use `!!` or `test::`).
- Per-test setup/teardown: `test::@setup(&setup_fn, &teardown_fn);` inside the test.
- Test-only builds have `env::TESTING` true; memory is poisoned (0xAA new, 0xBA freed byte).
- Put tests next to the code (`@test` section) or in `test/` (project `test-sources`).
- Typical cases: empty/max inputs, every `excuse` path (`test::@error`), round-trips
  (encode→decode), ownership (allocate with `mem`, rely on the leak checker).

## Benchmarks

`fn void bench_x() @benchmark { ... }` → `c3c benchmark` / `c3c compile-benchmark f.c3`,
`set_benchmark_warmup_iterations(n)` / `set_benchmark_max_iterations(n)` in an `@init`
function, `--benchmark-csv-report`. Benchmark at the optimization level you ship.

## Debugging

| Tool | How |
|---|---|
| Backtraces | automatic on panic/trap in safe builds; `backtrace::get(tmem)` (`std::os::backtrace`) for manual capture |
| gdb / lldb | debug info is on by default (`-g`); C3 symbols are module-qualified (`mymod__fn` style) |
| ASan / TSan / MSan | `--sanitize=address\|thread\|memory` |
| Temp-memory misuse | `-D VMEM_TEMP`: freed temp pages segfault on access |
| Leaks in a region | `@assert_leak() { ... };`, `mem::@report_heap_allocs_in_scope() { ... };`, `TrackingAllocator` |
| Integer wrap bugs | `--trap-on-wrap` (or project `"trap-on-wrap": true`) |
| Compile-time values | `$echo expr;`, `$assert(cond)`, `$error "msg %s", x;` |
| Print anything | `io::printfn("%s", value)` (`%s` handles all types), `io::printn(struct)` lists fields |

Reading panics: the first frame in *your* module is usually the bug; contract violations name
the `@require` that failed (pinpointed per parameter with `@require [param]`).

## Common compile errors → fix (code written for older C3)

| Symptom / old code | Fix (0.8.5) |
|---|---|
| `def Foo = int;` | `alias Foo = int;` (0.7.0) |
| `distinct Id = int;` | `typedef Id = int;` (0.7.0; `distinct` alt removed again in 0.8.5) |
| `fn int! foo()` / `int! x` | `fn int? foo()` / `int? x` (0.7.0) |
| `fault MyErr { A, B }` / `anyfault` | `excuse A, B;` (or `faultdef` pre-0.8.4) / `fault` |
| `return MyErr.A?;` / `io::EOF?` | `return A~;` / `io::EOF~` (0.7.9, old form removed 0.8.0) |
| `List(<int>)`, `module foo(<Type>)`, `module foo {Type}` | `List{int}`, `module foo <Type>` |
| `int.sizeof`, `$sizeof(x)`, `$alignof`, `$offsetof`, `$nameof`, `.nameof` | `int::size`, `@sizeof(x)`, `Type::alignment`, `$reflect(T.f).offset`, `::name`, `.description` |
| `$typeof(x)`, `$typefrom(...)` | `$Typeof(x)`, `$Typefrom(...)` (0.8.0) |
| `isz` | `sz` (0.8.0) |
| "cannot implicitly convert … signed/unsigned" | add an explicit cast; prefer `sz`/`int` over `usz`/`uint` (0.8.0) |
| `typedef Foo = int; Foo f = 1;` error | `typedef Foo @constinit = int;` or `(Foo)1` (0.7.10/0.8.0) |
| `MyEnum e = x + 1;` | `MyEnum::from_ordinal(x.ordinal + 1)` or `e++` (wraps) (0.8.0) |
| `enum Foo : inline int` / `enum Foo : const` | `constset Foo : inline int { ... }` |
| `$foreach ($x : $list)`, `$switch ($T)`, `$for (...)` | `$foreach $x : $list:`, `$switch $T:`, `$for ...:` (0.7.0) |
| `@if(env::WIN32)` on top-level decl, `$feature(X)` | `@feat(WIN32)`, `$feat(X)` (0.8.3) |
| `@extern("name")` | `@cname("name")` (0.8.0) |
| `$vacount`, `$vasplat`, `$vaexpr(i)` | `$vaarg.len`, `...$vaarg`, `$vaarg[i]` |
| `$member.get(v)` | `v.$member` (0.8.1) |
| `var x = ...;` in a function | give the type, or `var x @safeinfer = ...;` |
| `if (x = foo())` | `if ((x = foo()))` |
| `SubProcess`, `process::create` | `Process`, `process::spawn` (0.7.11/0.8.0) |
| `json::parse_string(s)` / `json::parse(stream)` | `json::parse(mem, s)` / `json::load(mem, stream)` (0.8.0) |
| `catch` on `mutex.lock()`/`destroy()` | they return `void`/`@maydiscard` now (0.8.0) |
| `while (true) { if (catch err = s.read(buf)) { if (err == io::EOF) break; } }` | `InStream.read` returns `0` at EOF since 0.8.4 |

When an error mentions a stdlib symbol you didn't expect, look it up:
`scripts/std-find.sh <name>` and `scripts/docs.sh -r <version>` for when it changed.
