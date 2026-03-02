const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "metal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Link macOS frameworks to the executable
    exe.linkFramework("AppKit");
    exe.linkFramework("Metal");
    exe.linkFramework("MetalKit");
    exe.linkFramework("QuartzCore");
    exe.linkFramework("JavaScriptCore");
    exe.linkSystemLibrary("objc");

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Link same frameworks to tests
    exe_tests.linkFramework("AppKit");
    exe_tests.linkFramework("Metal");
    exe_tests.linkFramework("MetalKit");
    exe_tests.linkFramework("QuartzCore");
    exe_tests.linkFramework("JavaScriptCore");
    exe_tests.linkSystemLibrary("objc");

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
