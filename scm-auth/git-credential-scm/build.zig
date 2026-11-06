const std = @import("std");
const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", manifest.version);

    const exe = b.addExecutable(.{
        .name = "git-credential-scm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", options);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Run git-credential-scm").dependOn(&run_cmd.step);

    // Every module is reachable from src/main.zig, so one test binary covers
    // them all (including the fuzz tests, run once with their corpus).
    const tests = b.addTest(.{ .root_module = exe.root_module });
    b.step("test", "Run all unit tests").dependOn(&b.addRunArtifact(tests).step);

    // Only the fuzz tests; `zig build fuzz --fuzz` fuzzes them continuously.
    const fuzz_tests = b.addTest(.{
        .name = "fuzz",
        .root_module = exe.root_module,
        .filters = &.{"fuzz"},
    });
    b.step("fuzz", "Run the fuzz tests (add --fuzz to fuzz continuously)").dependOn(&b.addRunArtifact(fuzz_tests).step);

    // Developer smoke test against a real Secret Service; never installed.
    const smoke = b.addExecutable(.{
        .name = "scm-dbus-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/smoke.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const smoke_run = b.addRunArtifact(smoke);
    smoke_run.addPassthruArgs();
    b.step("smoke", "Open and close a Secret Service session (reads no items)").dependOn(&smoke_run.step);
}
