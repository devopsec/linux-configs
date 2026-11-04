# C interop (verified on 0.17 + translate-c `zig-0.17.x` branch)

## Importing C headers

| Zig | How |
|---|---|
| ≤ 0.15 | `const c = @cImport({ @cInclude("stdio.h"); });` |
| 0.16 | `@cImport` deprecated → `b.addTranslateC(...)` step + `@import("c")` |
| **0.17+** | `@cImport` **removed**; use the `translate_c` package (Codeberg) |

```bash
# Pick the branch matching the compiler: main tracks Zig master.
zig fetch --save=translate_c "git+https://codeberg.org/ziglang/translate-c#zig-0.17.x"
```

```zig
// build.zig
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c: Translator = .init(b.dependency("translate_c", .{}), .{
        .c_source_file = b.path("src/c.h"),          // a stub header with the #includes you need
        .target = target,
        .optimize = optimize,
        .link_system_libs = &.{.{ .name = "sqlite3" }},  // links the module + finds headers
        .warnings = .show,
    });
    c.addIncludePath(b.path("vendor/include"));      // also: defineCMacro, linkLibrary, addConfigHeader
    c.run.addArg("-Wno-pragma-once-outside-header"); // raw Aro args if needed

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "c", .module = c.mod }},
        }),
    });
    b.installArtifact(exe);
}
```

```c
/* src/c.h */
#define _GNU_SOURCE
#include <sqlite3.h>
```

```zig
// src/main.zig
const c = @import("c");
```

- Inspect translated output when a symbol is missing or mistranslated:
  `zig translate-c -I vendor/include src/c.h | less` (CLI still ships; same `-target` as the
  build) or the `t.output_file` LazyPath.
- Function-like macros often fail to translate — re-implement them in Zig.
- `std.c` already declares much of libc (`std.c.getpid`, `std.c.malloc`, …) for linked-libc
  builds; prefer it for a handful of calls instead of translating headers.

## Declaring C symbols by hand

```zig
extern "c" fn strlen(s: [*:0]const u8) usize;                    // needs link_libc
extern "sqlite3" fn sqlite3_libversion() [*:0]const u8;
const Opaque = opaque {};                                         // incomplete C struct
extern fn lib_new() ?*Opaque;
```

## Type mapping

| C | Zig |
|---|---|
| `int`, `long`, `size_t`, `char` | `c_int`, `c_long`, `usize`, `c_char` (or `u8` for bytes) |
| `T*` (nullable, unknown length) | `[*c]T` from translate-c; tighten to `?*T`, `*T`, `[*]T`, `?[*:0]const u8` in your wrappers |
| `const char*` string | `[*:0]const u8`; Zig → C: `"lit"` coerces; slices need a `[:0]` (`gpa.dupeSentinel(u8, s, 0)`) |
| `void*` | `?*anyopaque` |
| struct | `extern struct` (never plain `struct` across the ABI) |
| enum | `c_int` constants or `enum(c_int)` |
| bitfields | hand-written accessors; translate-c may demote to opaque |
| callbacks | `*const fn (...) callconv(.c) T` |
| varargs | `fn f(fmt: [*:0]const u8, ...) callconv(.c) c_int`; `@cVaStart` etc. inside |

C → Zig string: `std.mem.span(ptr)` gives `[:0]const u8`.

## Exporting Zig to C

```zig
export fn add(a: c_int, b: c_int) c_int {           // C ABI, unmangled
    return a + b;
}

pub fn callback(ctx: ?*anyopaque, n: c_int) callconv(.c) void { … }
```

```zig
// build.zig — shared library + header-less consumers
const lib = b.addLibrary(.{
    .name = "mylib",
    .linkage = .dynamic,
    .root_module = b.createModule(.{ .root_source_file = b.path("src/c_api.zig"), .target = target, .optimize = optimize }),
});
b.installArtifact(lib);
```

Write the matching `.h` by hand (auto header emission is not reliable). Keep panics from crossing
the boundary: exported functions return error codes, never Zig errors.

## Compiling C/C++ sources

```zig
mod.addCSourceFiles(.{
    .root = b.path("vendor/lib"),
    .files = &.{ "a.c", "b.c" },
    .flags = &.{ "-std=c11", "-Wall", "-Wextra" },
});
mod.link_libc = true;          // or link_libcpp for C++ (.cpp files)
```

`zig cc` / `zig c++` are drop-in clang drivers with bundled cross libcs:
`CC="zig cc -target x86_64-linux-musl" make`.

## Pitfalls

- Ownership across the boundary: memory from C `malloc` → free with C `free` (or
  `std.heap.c_allocator`), never with a Zig allocator, and vice versa.
- C code compiled by Zig gets UBSan-style traps in Debug (`-fsanitize=undefined` defaults);
  a trap in C code is usually a real C bug. Disable per module only with justification
  (`.sanitize_c = .off`).
- `[*c]T` allows null and arithmetic like C; convert to a precise pointer type at the first
  Zig-side boundary so the rest of the code gets safety checks.
