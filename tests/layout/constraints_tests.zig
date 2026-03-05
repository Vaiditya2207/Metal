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


test "layout: min-width constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    try style.applyProperty("width", "100px", allocator);
    try style.applyProperty("min-width", "200px", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = &dummy_node, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800.0, .viewport_height = 600.0 });

    // Width=100, Min=200 -> should be 200
    try std.testing.expectEqual(@as(f32, 200.0), root.dimensions.content.width);
}

test "layout: max-width constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    try style.applyProperty("width", "300px", allocator);
    try style.applyProperty("max-width", "200px", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = &dummy_node, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800.0, .viewport_height = 600.0 });

    // Width=300, Max=200 -> should be 200
    try std.testing.expectEqual(@as(f32, 200.0), root.dimensions.content.width);
}

test "layout: min-height constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    try style.applyProperty("height", "100px", allocator);
    try style.applyProperty("min-height", "200px", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = &dummy_node, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800.0, .viewport_height = 600.0 });

    // Height=100, Min=200 -> should be 200
    try std.testing.expectEqual(@as(f32, 200.0), root.dimensions.content.height);
}

test "layout: max-height constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    try style.applyProperty("height", "300px", allocator);
    try style.applyProperty("max-height", "200px", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = &dummy_node, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800.0, .viewport_height = 600.0 });

    // Height=300, Max=200 -> should be 200
    try std.testing.expectEqual(@as(f32, 200.0), root.dimensions.content.height);
}

test "layout: min-width with border-box" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    style.box_sizing = .border_box;
    try style.applyProperty("width", "100px", allocator);
    try style.applyProperty("min-width", "200px", allocator);
    try style.applyProperty("padding", "10px", allocator);
    try style.applyProperty("border-width", "5px", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = &dummy_node, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800.0, .viewport_height = 600.0 });

    // MinWidth=200 (border-box) -> content min-width = 200 - 30 = 170
    // Width=100 (border-box) -> content width = 100 - 30 = 70
    // Result should be 170
    try std.testing.expectEqual(@as(f32, 170.0), root.dimensions.content.width);
}
