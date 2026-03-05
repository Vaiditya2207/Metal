const std = @import("std");
const dom = @import("../../src/dom/mod.zig");
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

const properties = @import("../../src/css/properties.zig");
const layout = @import("../../src/layout/mod.zig");
const values = @import("../../src/css/values.zig");

test "flex shrink basic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.width = .{ .value = 300, .unit = .px };

    var child1_style = properties.ComputedStyle{};
    child1_style.display = .block;
    child1_style.width = .{ .value = 200, .unit = .px };
    child1_style.flex_shrink = 1;

    var child2_style = properties.ComputedStyle{};
    child2_style.display = .block;
    child2_style.width = .{ .value = 200, .unit = .px };
    child2_style.flex_shrink = 1;

    var child1_node = resolver.StyledNode{ .node = &dummy_node, .style = child1_style, .children = &.{} };
    var child2_node = resolver.StyledNode{ .node = &dummy_node, .style = child2_style, .children = &.{} };

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = &.{},
    };
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child1_node;
    c_children[1] = &child2_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 300, .viewport_height = 600 });

    // Container 300px, two children 200px each (total 400). Overflow = 100.
    // Both shrink=1, equal base sizes => each shrinks by 50. Result: 150 each.
    try std.testing.expectEqual(@as(f32, 150), root.children.items[0].dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 150), root.children.items[1].dimensions.content.width);
}

test "flex shrink proportional" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.width = .{ .value = 300, .unit = .px };

    var child1_style = properties.ComputedStyle{};
    child1_style.display = .block;
    child1_style.width = .{ .value = 200, .unit = .px };
    child1_style.flex_shrink = 1;

    var child2_style = properties.ComputedStyle{};
    child2_style.display = .block;
    child2_style.width = .{ .value = 200, .unit = .px };
    child2_style.flex_shrink = 3;

    var child1_node = resolver.StyledNode{ .node = &dummy_node, .style = child1_style, .children = &.{} };
    var child2_node = resolver.StyledNode{ .node = &dummy_node, .style = child2_style, .children = &.{} };

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = &.{},
    };
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child1_node;
    c_children[1] = &child2_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 300, .viewport_height = 600 });

    // Overflow = 100. Weighted shrink: A=1*200=200, B=3*200=600. Total=800.
    // A shrinks: (200/800)*100 = 25 => 175. B shrinks: (600/800)*100 = 75 => 125.
    try std.testing.expectEqual(@as(f32, 175), root.children.items[0].dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 125), root.children.items[1].dimensions.content.width);
}

test "flex shrink zero prevents shrink" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.width = .{ .value = 200, .unit = .px };

    var child1_style = properties.ComputedStyle{};
    child1_style.display = .block;
    child1_style.width = .{ .value = 150, .unit = .px };
    child1_style.flex_shrink = 0;

    var child2_style = properties.ComputedStyle{};
    child2_style.display = .block;
    child2_style.width = .{ .value = 150, .unit = .px };
    child2_style.flex_shrink = 1;

    var child1_node = resolver.StyledNode{ .node = &dummy_node, .style = child1_style, .children = &.{} };
    var child2_node = resolver.StyledNode{ .node = &dummy_node, .style = child2_style, .children = &.{} };

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = &.{},
    };
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child1_node;
    c_children[1] = &child2_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 200, .viewport_height = 600 });

    // Overflow = 100. A: shrink=0 (no shrink). B: shrink=1.
    // Weighted: A=0*150=0, B=1*150=150. Total=150.
    // A shrinks 0 => stays 150. B shrinks (150/150)*100 = 100 => 50.
    try std.testing.expectEqual(@as(f32, 150), root.children.items[0].dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 50), root.children.items[1].dimensions.content.width);
}
