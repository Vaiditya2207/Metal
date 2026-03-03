const std = @import("std");
const layout = @import("../../src/layout/mod.zig");
const properties = @import("../../src/css/properties.zig");
const resolver = @import("../../src/css/resolver.zig");

test "layout: margin auto centering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    try style.applyProperty("width", "100px", allocator);
    try style.applyProperty("margin-left", "auto", allocator);
    try style.applyProperty("margin-right", "auto", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = undefined, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    // Viewport width 500. Block width 100. Available 400. Margins should be 200 each.
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 500.0, .viewport_height = 600.0 });

    try std.testing.expectEqual(@as(f32, 200.0), root.dimensions.margin.left);
    try std.testing.expectEqual(@as(f32, 200.0), root.dimensions.margin.right);
    try std.testing.expectEqual(@as(f32, 100.0), root.dimensions.content.width);
    // X position should be margin-left (200) relative to parent (0) => 200
    try std.testing.expectEqual(@as(f32, 200.0), root.dimensions.content.x);
}

test "layout: margin-left auto only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    try style.applyProperty("width", "100px", allocator);
    try style.applyProperty("margin-left", "auto", allocator);
    try style.applyProperty("margin-right", "10px", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = undefined, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    // Viewport 500. Width 100. Right 10. Available 390. Left gets 390.
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 500.0, .viewport_height = 600.0 });

    try std.testing.expectEqual(@as(f32, 390.0), root.dimensions.margin.left);
    try std.testing.expectEqual(@as(f32, 10.0), root.dimensions.margin.right);
}
