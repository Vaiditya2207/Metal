const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "metal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add Objective-C bridge
    exe.addCSourceFile(.{
        .file = b.path("src/platform/objc_bridge.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    exe.addCSourceFile(.{
        .file = b.path("src/platform/metal_render.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    exe.addCSourceFile(.{
        .file = b.path("src/platform/text_atlas.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    exe.addCSourceFile(.{
        .file = b.path("src/platform/event_bridge.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    exe.addCSourceFile(.{
        .file = b.path("src/platform/jsc_bridge.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    exe.addCSourceFile(.{
        .file = b.path("src/platform/jsc_bridge_ext.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    exe.addCSourceFile(.{
        .file = b.path("src/platform/net_bridge.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    exe.addCSourceFile(.{
        .file = b.path("src/platform/image_bridge.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    exe.addIncludePath(b.path("src/platform"));

    // Link macOS frameworks
    exe.linkFramework("AppKit");
    exe.linkFramework("Foundation");
    exe.linkFramework("Metal");
    exe.linkFramework("MetalKit");
    exe.linkFramework("QuartzCore");
    exe.linkFramework("CoreText");
    exe.linkFramework("CoreGraphics");
    exe.linkFramework("JavaScriptCore");
    exe.linkFramework("ImageIO");
    exe.linkLibC();

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step — single entry point that imports all testable modules
    const test_step = b.step("test", "Run unit tests");

    const all_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    all_tests.addIncludePath(b.path("src/platform"));
    all_tests.addCSourceFile(.{
        .file = b.path("src/platform/event_bridge.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    all_tests.addCSourceFile(.{
        .file = b.path("src/platform/net_bridge.m"),
        .flags = &[_][]const u8{ "-fobjc-arc", "-Isrc/platform" },
    });
    all_tests.linkFramework("AppKit");
    all_tests.linkFramework("Foundation");
    all_tests.linkFramework("MetalKit");
    all_tests.linkFramework("Metal");
    all_tests.linkLibC();
    test_step.dependOn(&b.addRunArtifact(all_tests).step);
}
