const std = @import("std");
const layout = @import("../../src/layout/mod.zig");
const values = @import("../../src/css/values.zig");

test "em resolves relative to element font size not root" {
    const ctx = layout.LayoutContext{
        .allocator = std.testing.allocator,
        .viewport_width = 800,
        .viewport_height = 600,
        .root_font_size = 16.0,
    };
    const length = values.Length{ .value = 2.0, .unit = .em };
    // Element font size is 24px, so 2em = 48px
    const result = layout.resolveLength(length, 800, ctx, 24.0);
    try std.testing.expectEqual(@as(f32, 48.0), result);
}

test "rem still resolves relative to root font size" {
    const ctx = layout.LayoutContext{
        .allocator = std.testing.allocator,
        .viewport_width = 800,
        .viewport_height = 600,
        .root_font_size = 16.0,
    };
    const length = values.Length{ .value = 2.0, .unit = .rem };
    // 2rem = 2 * 16 = 32px regardless of element font size
    const result = layout.resolveLength(length, 800, ctx, 24.0);
    try std.testing.expectEqual(@as(f32, 32.0), result);
}

test "px resolves to its value" {
    const ctx = layout.LayoutContext{
        .allocator = std.testing.allocator,
        .viewport_width = 800,
        .viewport_height = 600,
        .root_font_size = 16.0,
    };
    const length = values.Length{ .value = 42.0, .unit = .px };
    const result = layout.resolveLength(length, 800, ctx, 16.0);
    try std.testing.expectEqual(@as(f32, 42.0), result);
}

test "percent resolves relative to containing size" {
    const ctx = layout.LayoutContext{
        .allocator = std.testing.allocator,
        .viewport_width = 800,
        .viewport_height = 600,
        .root_font_size = 16.0,
    };
    const length = values.Length{ .value = 50.0, .unit = .percent };
    const result = layout.resolveLength(length, 400, ctx, 16.0);
    try std.testing.expectEqual(@as(f32, 200.0), result);
}

test "em and rem differ when element font size differs from root" {
    const ctx = layout.LayoutContext{
        .allocator = std.testing.allocator,
        .viewport_width = 800,
        .viewport_height = 600,
        .root_font_size = 16.0,
    };
    const em_length = values.Length{ .value = 1.0, .unit = .em };
    const rem_length = values.Length{ .value = 1.0, .unit = .rem };
    // With element font size 32px: 1em = 32, 1rem = 16
    const em_result = layout.resolveLength(em_length, 800, ctx, 32.0);
    const rem_result = layout.resolveLength(rem_length, 800, ctx, 32.0);
    try std.testing.expectEqual(@as(f32, 32.0), em_result);
    try std.testing.expectEqual(@as(f32, 16.0), rem_result);
}

test "null length resolves to zero" {
    const ctx = layout.LayoutContext{
        .allocator = std.testing.allocator,
        .viewport_width = 800,
        .viewport_height = 600,
        .root_font_size = 16.0,
    };
    const result = layout.resolveLength(null, 800, ctx, 24.0);
    try std.testing.expectEqual(@as(f32, 0.0), result);
}
