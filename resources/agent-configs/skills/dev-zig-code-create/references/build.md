# Build system and packages (verified on 0.17)

Canonical starting point for the installed version: `<lib_dir>/init/build.zig` and
`build.zig.zon` (`zig init` copies them). Diff against them when a build script fails after an
upgrade. CLI help: `zig build -h` (lists project steps and `-D` options).

## Contents
- Minimal build.zig
- build.zig.zon
- Dependencies
- Options, generated code, install layout
- Linking C and system libraries
- Cross-compilation and release builds
- 0.17 configure-cache rules
- Useful CLI

## Minimal build.zig (exe + library module + tests)

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Public module other packages can import as "mylib".
    const mod = b.addModule("mylib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "mytool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "mylib", .module = mod }},
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();                 // 0.17: `zig build run -- a b`; b.args is gone
    b.step("run", "Run the app").dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    for ([_]*std.Build.Module{ mod, exe.root_module }) |m| {
        const t = b.addTest(.{ .root_module = m });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
```

Rules:
- Every compile step takes `.root_module` (0.15+). `root_source_file`/`target`/`optimize` on
  `addExecutable` itself are gone.
- Libraries: `b.addLibrary(.{ .name = "foo", .linkage = .static, .root_module = … })`
  (`.dynamic` for shared; `addStaticLibrary`/`addSharedLibrary` are gone).
- Module-level settings (0.16+) live on `Module`, not `Compile`: `mod.addIncludePath`,
  `mod.addCSourceFiles`, `mod.linkSystemLibrary`, `mod.linkLibrary`, `mod.addCMacro`, and
  `.link_libc = true` in `createModule` options.
- `build` may return `!void` (needed when calling `b.dependencyLazy`).

## build.zig.zon

```zig
.{
    .name = .mytool,                         // enum literal, not a string (0.14+)
    .version = "0.1.0",
    .fingerprint = 0x1a2b3c4d5e6f7081,       // generated once by zig; never hand-edit/copy
    .minimum_zig_version = "0.17.0",
    .dependencies = .{
        .zstd = .{ .url = "git+https://codeberg.org/owner/zstd#<commit>", .hash = "…" },
        .local_dep = .{ .path = "../local_dep" },
        .optional_thing = .{ .url = "…", .hash = "…", .lazy = true },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src", "LICENSE" },
}
```

- Missing/invalid fingerprint: delete the line and run `zig build`; it prints the value to add.
  Forks of maintained projects must regenerate it.
- `minimum_zig_version` is what `scripts/zig-env.sh` compares against the installed compiler.

## Dependencies

```bash
zig fetch --save git+https://codeberg.org/ziglang/translate-c   # adds url+hash to build.zig.zon
zig fetch --save=name https://example.com/pkg-1.2.3.tar.gz
zig build --fetch                                             # prefetch everything (then offline)
zig build --fork=../my-checkout                               # temp override by name+fingerprint
```

```zig
const dep = b.dependency("zstd", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zstd", dep.module("zstd"));     // Zig module exported by the package
exe.root_module.linkLibrary(dep.artifact("zstd"));         // compiled C/Zig library artifact

// Lazy dependency (fetched only when used):
pub fn build(b: *std.Build) !void {
    const dep = try b.dependencyLazy("optional_thing", .{});   // 0.17; lazyDependency deprecated
    _ = dep;
}
```

- Fetched packages land in `zig-pkg/` next to `build.zig` (0.16+) — add it to `.gitignore`
  along with `.zig-cache/` and `zig-out/`.
- Never invent a `.hash`; always obtain it via `zig fetch`. Pin `git+…#<commit>` or release
  tarballs, not moving branches.

## Options, generated code, install layout

```zig
const enable_tracy = b.option(bool, "tracy", "Enable Tracy profiling") orelse false;
const opts = b.addOptions();
opts.addOption(bool, "tracy", enable_tracy);
opts.addOption([]const u8, "version", "0.1.0");
exe.root_module.addOptions("build_options", opts);     // @import("build_options").tracy

exe.root_module.addAnonymousImport("schema", .{ .root_source_file = b.path("data/schema.zon") });
b.installFile("README.md", "share/doc/mytool/README.md");
```

- Generated files: `b.addWriteFiles()` / `addRunArtifact(gen).addOutputFileArg("out.zig")`
  return `LazyPath`s; feed them to `root_source_file` or `addImport`. Never write into the
  source tree from build.zig.
- `@embedFile("data.bin")` embeds files inside the module's directory tree; for files outside,
  add an anonymous import or a WriteFiles step.
- Install prefix: `zig-out/` (`-p <prefix>` to change). `b.getInstallStep()` is the default step.

## Linking C and system libraries

```zig
const mod = exe.root_module;
mod.link_libc = true;                                   // or .link_libc = true in createModule
mod.linkSystemLibrary("sqlite3", .{});                  // pkg-config by default (0.17)
mod.linkSystemLibrary("ws2_32", .{ .use_pkg_config = .no });
mod.addIncludePath(b.path("vendor/include"));
mod.addCSourceFiles(.{ .files = &.{ "vendor/a.c", "vendor/b.c" }, .flags = &.{ "-std=c11", "-Wall" } });
```

C headers → Zig: see `c-interop.md` (0.17 uses the external `translate_c` package).

## Cross-compilation and release builds

```bash
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe    # static Linux binary
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast
zig build -Dtarget=x86_64-windows-gnu
zig build --release=safe                                       # if build.zig sets preferred_optimize_mode
zig targets | less                                             # supported triples, CPUs, libcs
```

Zig ships libc headers/sources for musl, glibc (pick version: `-Dtarget=x86_64-linux-gnu.2.31`),
mingw-w64 and macOS — cross-compiling needs no extra toolchain unless you link system libraries
from the target. Run foreign binaries in tests with `-fqemu` / `-fwine` / `-fwasmtime`.

## 0.17 configure-cache rules (configurer/maker split)

`build.zig` now runs once to produce a cached build graph; a separate maker executes it.
Side effects the cache cannot see "poison" it and force re-configuration:

| Avoid | Use |
|---|---|
| reading `b.args` | `run.addPassthruArgs()` |
| `b.findProgram(...)` at configure time | `b.findProgramLazy(...)` → `LazyPath` |
| reading files/dirs directly in build.zig | `b.dependOnFileContents(path)` / `dependOnFileMetadata` / `dependOnDirectoryContents` |
| `b.build_root` (Directory) | `b.root` (`Cache.Path`) |
| `addOptionPath` for directories | `addOptionPathDirectory` (files: `addOptionPath`) |

`--cache-poison=pure|poisoned|disallowed|ignored` controls enforcement (`disallowed` is useful in
CI to catch impure build scripts).

## Useful CLI

```bash
zig build -l                          # list steps
zig build test --summary all          # per-step results (failures is the default when short)
zig build test -Dtest-filter=parse    # only if build.zig wires filters: .filters = b.option(...)
zig build test --test-timeout 5s      # kill hung tests (units: ns us ms s m h)
zig build --watch -fincremental       # rebuild on change (incremental: experimental)
zig build -j4 --maxrss 4G             # limit parallelism / memory
zig build --verbose                   # show compiler invocations
```

Wire test filters explicitly when wanted:

```zig
const filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match") orelse &.{};
const t = b.addTest(.{ .root_module = mod, .filters = filters });
```
