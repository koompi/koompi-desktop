// KOOMPI installer - build script. Builds with Zig 0.16 and 0.17.
//
// The default target is x86_64-linux-musl and nothing links libc, so
// `zig build -Doptimize=ReleaseSafe` gives the same static binary on any
// build host: zig-out/bin/koompi-installer.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    });
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{ .name = "koompi-installer", .root_module = root_module });
    b.installArtifact(exe);

    // Tests run on the build host.
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = test_module });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
