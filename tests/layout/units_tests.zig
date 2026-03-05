const std = @import("std");
const dom = @import("../../src/dom/mod.zig");
const layout = @import("../../src/layout/mod.zig");
const properties = @import("../../src/css/properties.zig");
const resolver = @import("../../src/css/resolver.zig");

var dummy_node = dom.Node{
    .allocator = undefined,
    .node_type = .element,
    .tag = .div,
    .tag_name_str = null,
    .attributes = .{},
    .children = .{},
    .data = null,
};

const values = @import("../../src/css/values.zig");

test "layout: units resolution (px, em, rem, vw, vh, %)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    // Test px (base case)
    try style.applyProperty("width", "100px", allocator);
    // Test em (relative to element font size, which defaults to 16px)
    try style.applyProperty("height", "2em", allocator);
    // Test rem (relative to root font size)
    try style.applyProperty("margin-top", "1.5rem", allocator);
    // Test vw (viewport width)
    try style.applyProperty("margin-right", "10vw", allocator);
    // Test vh (viewport height)
    try style.applyProperty("margin-bottom", "5vh", allocator);
    // Test % (relative to containing block)
    try style.applyProperty("margin-left", "50%", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{
        .node = &dummy_node,
        .style = style,
        .children = &[_]*resolver.StyledNode{},
    };

    var root = layout.LayoutBox.init(.blockNode, sn);

    // Layout with specific viewport and root font size
    // Viewport: 800x600
    // Root font size: 20px (element font size remains default 16px)
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800.0, .viewport_height = 600.0, .root_font_size = 20.0 });

    // 100px -> 100
    try std.testing.expectEqual(@as(f32, 100.0), root.dimensions.content.width);

    // 2em -> 2 * 16 (element font size) = 32
    try std.testing.expectEqual(@as(f32, 32.0), root.dimensions.content.height);

    // 1.5rem -> 1.5 * 20 (root font size) = 30
    try std.testing.expectEqual(@as(f32, 30.0), root.dimensions.margin.top);

    // 10vw -> 10% of 800 = 80
    try std.testing.expectEqual(@as(f32, 80.0), root.dimensions.margin.right);

    // 5vh -> 5% of 600 = 30
    try std.testing.expectEqual(@as(f32, 30.0), root.dimensions.margin.bottom);

    // 50% -> 50% of containing block (viewport width 800) = 400
    try std.testing.expectEqual(@as(f32, 400.0), root.dimensions.margin.left);
}
