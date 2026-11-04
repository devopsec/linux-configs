# Testing and debugging (verified on 0.17)

## Unit tests

```zig
const std = @import("std");
const testing = std.testing;

test "parse rejects empty input" {
    try testing.expectError(error.Empty, parse(""));
}

test "round trip through a temp dir" {
    const io = testing.io;                     // test-runner Io (Threaded)
    const gpa = testing.allocator;             // fails the test on leak/double free
    var tmp = testing.tmpDir(.{});             // under .zig-cache/tmp/<random>
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a.txt", .data = "hi" });
    const got = try tmp.dir.readFileAlloc(io, "a.txt", gpa, .limited(64));
    defer gpa.free(got);
    try testing.expectEqualStrings("hi", got);
}

test {
    testing.refAllDecls(@This());              // compile (and run tests of) every pub decl
    _ = @import("parser.zig");                 // pull tests from other files into this binary
}
```

- Assertions: `expect`, `expectEqual(expected, actual)` (expected first; it is `inline` so the
  expected literal adopts the actual's type), `expectEqualSlices(T, …)`, `expectEqualStrings`,
  `expectEqualDeep`, `expectError`, `expectFmt`, `expectApproxEqAbs/Rel`,
  `expectStringStartsWith`.
- Skip conditionally: `return error.SkipZigTest;`.
- Tests are lazily compiled: a file's tests run only if the file is reachable from the test
  root — add `_ = @import(...)` or `refAllDecls` in the root.
- Doctests: `test parse { … }` (identifier, not string) attaches the test to `parse` in docs.
- `builtin.is_test` gates test-only code; `testing.log_level` raises log verbosity in tests.
- Running: `zig build test` (via build.zig), or single file `zig test src/foo.zig
  --test-filter "parse"`; hung tests: `zig build test --test-timeout 10s`.

## Allocation-failure testing

```zig
fn buildIndex(gpa: std.mem.Allocator, words: []const []const u8) !void {
    var map: std.StringHashMapUnmanaged(u32) = .empty;
    defer map.deinit(gpa);
    for (words) |w| try map.put(gpa, w, 1);
}

test "buildIndex survives every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, buildIndex, .{&.{ "a", "b" }});
}
```

The function under test takes the allocator as its **first** parameter; extra args go in the
tuple. Any leak or missing `errdefer` on a failure path fails the test. `testing.failing_allocator`
always fails (OOM path smoke test).

## Fuzzing (0.15+ built-in; `*std.testing.Smith` input since 0.16/0.17)

```zig
test "fuzz parser" {
    try testing.fuzz({}, fuzzOne, .{});
}

fn fuzzOne(_: void, smith: *testing.Smith) !void {
    var buf: [256]u8 = undefined;
    const len = smith.valueRangeAtMost(u8, 0, buf.len - 1);
    smith.bytes(buf[0..len]);
    _ = parse(buf[0..len]) catch return;      // must never crash/leak; errors are fine
}
```

`zig build test` runs each fuzz test once with smith-generated input; `zig build test --fuzz`
starts continuous fuzzing with a web UI (`--fuzz=<limit>` to bound it). The corpus is kept in
the cache — commit interesting inputs as regular regression tests.

## Debugging

- `std.debug.print("{any}\n", .{x})` — stderr, works anywhere, remove before finishing.
- `@compileLog(T, value)` — comptime inspection (always a compile error; remove after).
- `std.debug.dumpCurrentStackTrace(.{})`, `dumpErrorReturnTrace(trace)` in custom handlers.
- `-freference-trace[=N]` on `zig build`/`zig test` shows *why* a declaration was analyzed —
  essential for "error in std" messages caused by your call site.
- Debug builds include DWARF: `gdb`/`lldb` work directly on `zig-out/bin/<exe>`; break on
  panics with `break std.debug.panicExtra` (or the panic handler shown in the trace).
- Valgrind works on Debug builds; `std.valgrind` client requests are available.
- Panics show the safety check that fired (index out of bounds, integer overflow, …) and a
  stack trace — read the first frame in *your* code, not the std frames.

## Common compile errors → fix (0.15–0.17)

| Error text (abridged) | Cause | Fix |
|---|---|---|
| `local variable is never mutated` | `var` that could be `const` | make it `const` |
| `unused local constant` / `unused function parameter` | strict unused checks | use it, or `_ = x;` if truly intentional |
| `expected N argument(s), found M` on `ArrayList`/map methods | unmanaged containers | pass the allocator: `list.append(gpa, x)` |
| `no member named 'getStdOut'` / `'cwd'` in `fs` | pre-0.16 I/O | `std.Io.File.stdout()`, `std.Io.Dir.cwd()` + `io` param |
| `no member named 'Mutex' in 'Thread'` / `'Pool'` | 0.16 moved sync into Io | `std.Io.Mutex`, `std.Io.Group` |
| `no field named 'root_source_file'` in `ExecutableOptions` | 0.15 build API | `.root_module = b.createModule(.{ … })` |
| `no field named 'args' in struct 'Build'` | 0.17 | `run_cmd.addPassthruArgs()` |
| `invalid format string '' for type 'T'` / `unused argument` | `{}` no longer calls `format` (0.15+) | use `{f}` for format methods, `{any}`, or an explicit specifier |
| `@cImport` / `@Type` invalid builtin | removed in 0.17 / 0.16 | translate_c package / `@Int`, `@Struct`, … |
| `cannot @bitCast … extern struct` | 0.17 logical-bit `@bitCast` | `@as(*align(1) const U, @ptrCast(&v)).*` or an `extern union` |
| `no field named 'fields' in struct 'lang.Type.Struct'` | 0.17 struct-of-arrays reflection | `info.field_names` / `field_types` / `field_attrs` |
| `use of undefined value here causes illegal behavior` | arithmetic on `undefined` (0.15+) | initialize first |
| `type 'X' has no members` / `@typeInfo(T).Struct` | 0.14+ lowercase tags | `.@"struct"`, `.int`, `.pointer` |
| `ambiguous operator precedence` | 0.18-dev partial precedence | add parentheses |
| `error: dependency loop detected` | self-referential comptime | split the type or move the computation |
