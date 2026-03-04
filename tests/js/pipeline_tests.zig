const std = @import("std");
const pipeline = @import("../../src/js/pipeline.zig");
const PipelineState = pipeline.PipelineState;

// --- PipelineState tests --------------------------------------------------------

test "PipelineState starts not dirty" {
    const ps = PipelineState.init();
    try std.testing.expect(!ps.isDirty());
}

test "markDirty sets dirty to true" {
    var ps = PipelineState.init();
    ps.markDirty();
    try std.testing.expect(ps.isDirty());
}

test "clearDirty resets to false" {
    var ps = PipelineState.init();
    ps.markDirty();
    try std.testing.expect(ps.isDirty());
    ps.clearDirty();
    try std.testing.expect(!ps.isDirty());
}

test "multiple markDirty calls remain dirty" {
    var ps = PipelineState.init();
    ps.markDirty();
    ps.markDirty();
    ps.markDirty();
    try std.testing.expect(ps.isDirty());
}

// --- Global get/set/reset tests -------------------------------------------------

test "getGlobal returns null initially" {
    pipeline.resetGlobal();
    try std.testing.expect(pipeline.getGlobal() == null);
}

test "setGlobal and getGlobal round-trip" {
    var ps = PipelineState.init();
    pipeline.setGlobal(&ps);
    defer pipeline.resetGlobal();
    const retrieved = pipeline.getGlobal();
    try std.testing.expect(retrieved != null);
    try std.testing.expect(!retrieved.?.isDirty());
}

test "resetGlobal clears global" {
    var ps = PipelineState.init();
    pipeline.setGlobal(&ps);
    pipeline.resetGlobal();
    try std.testing.expect(pipeline.getGlobal() == null);
}

// --- notifyDirty tests ----------------------------------------------------------

test "notifyDirty sets dirty via global" {
    var ps = PipelineState.init();
    pipeline.setGlobal(&ps);
    defer pipeline.resetGlobal();

    try std.testing.expect(!ps.isDirty());
    pipeline.notifyDirty();
    try std.testing.expect(ps.isDirty());
}

test "notifyDirty is safe when global is null" {
    pipeline.resetGlobal();
    // Should not crash
    pipeline.notifyDirty();
}
