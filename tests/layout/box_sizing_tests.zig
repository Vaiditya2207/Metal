const std = @import("std");
const layout = @import("../../src/layout/mod.zig");
const properties = @import("../../src/css/properties.zig");
const resolver = @import("../../src/css/resolver.zig");

test "layout: box-sizing border-box width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    style.box_sizing = .border_box;
    try style.applyProperty("width", "100px", allocator);
    try style.applyProperty("padding", "10px", allocator);
    try style.applyProperty("border-width", "5px", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = undefined, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800.0, .viewport_height = 600.0 });

    // Width = 100px (border-box)
    // Content width = 100 - (10+10 padding) - (5+5 border) = 100 - 30 = 70
    try std.testing.expectEqual(@as(f32, 70.0), root.dimensions.content.width);
}

test "layout: box-sizing content-box width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    style.box_sizing = .content_box;
    try style.applyProperty("width", "100px", allocator);
    try style.applyProperty("padding", "10px", allocator);
    try style.applyProperty("border-width", "5px", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = undefined, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800.0, .viewport_height = 600.0 });

    // Width = 100px (content-box)
    // Content width = 100
    try std.testing.expectEqual(@as(f32, 100.0), root.dimensions.content.width);
}
