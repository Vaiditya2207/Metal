const std = @import("std");
const resolver = @import("../../src/css/resolver.zig");
const properties = @import("../../src/css/properties.zig");
const layout = @import("../../src/layout/mod.zig");
const values = @import("../../src/css/values.zig");

test "flex row with flex-grow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Container: 500px wide, display: flex
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 500, .unit = .px };

    // Child 1: flex-grow: 1
    var child1_style = properties.ComputedStyle{};
    child1_style.display = .block;
    child1_style.flex_grow = 1;

    var child1_node = resolver.StyledNode{
        .node = undefined,
        .style = child1_style,
        .children = &.{},
    };

    // Child 2: flex-grow: 4
    var child2_style = properties.ComputedStyle{};
    child2_style.display = .block;
    child2_style.flex_grow = 4;

    var child2_node = resolver.StyledNode{
        .node = undefined,
        .style = child2_style,
        .children = &.{},
    };

    var container_node = resolver.StyledNode{
        .node = undefined, // not used by layout
        .style = container_style,
        .children = &.{},
    };
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child1_node;
    c_children[1] = &child2_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 500, .viewport_height = 600 });

    // Total width 500. Child 1 gets 1/5 = 100, Child 2 gets 4/5 = 400
    try std.testing.expectEqual(@as(f32, 100), root.children.items[0].dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 400), root.children.items[1].dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 0), root.children.items[0].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 100), root.children.items[1].dimensions.content.x);
}

test "flex row justify-content space-between" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.justify_content = .space_between;
    container_style.width = .{ .value = 500, .unit = .px };

    // Two children, each 100px wide
    var child1_style = properties.ComputedStyle{};
    child1_style.display = .block;
    child1_style.width = .{ .value = 100, .unit = .px };

    var child1_node = resolver.StyledNode{
        .node = undefined,
        .style = child1_style,
        .children = &.{},
    };

    var child2_node = resolver.StyledNode{
        .node = undefined,
        .style = child1_style,
        .children = &.{},
    };

    var container_node = resolver.StyledNode{
        .node = undefined,
        .style = container_style,
        .children = &.{},
    };
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child1_node;
    c_children[1] = &child2_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 500, .viewport_height = 600 });

    // Child 1 at 0, Child 2 at 400 (500 - 100)
    try std.testing.expectEqual(@as(f32, 0), root.children.items[0].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 400), root.children.items[1].dimensions.content.x);
}

test "flex column" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .column;
    container_style.width = .{ .value = 500, .unit = .px };

    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.height = .{ .value = 50, .unit = .px };

    var child1_node = resolver.StyledNode{ .node = undefined, .style = child_style, .children = &.{} };
    var child2_node = resolver.StyledNode{ .node = undefined, .style = child_style, .children = &.{} };

    var container_node = resolver.StyledNode{
        .node = undefined,
        .style = container_style,
        .children = &.{},
    };
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child1_node;
    c_children[1] = &child2_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 500, .viewport_height = 600 });

    // root.dimensions.content.height should be 100
    // Child 0 y should be 0, Child 1 y should be 50
    try std.testing.expectEqual(@as(f32, 0), root.children.items[0].dimensions.content.y);
    try std.testing.expectEqual(@as(f32, 50), root.children.items[1].dimensions.content.y);
    try std.testing.expectEqual(@as(f32, 100), root.dimensions.content.height);
}

test "flex align-items center" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.align_items = .center;
    container_style.height = .{ .value = 200, .unit = .px };
    container_style.width = .{ .value = 500, .unit = .px };

    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.height = .{ .value = 100, .unit = .px };
    child_style.width = .{ .value = 100, .unit = .px };

    var child_node = resolver.StyledNode{ .node = undefined, .style = child_style, .children = &.{} };

    var container_node = resolver.StyledNode{
        .node = undefined,
        .style = container_style,
        .children = &.{},
    };
    const c_children = try allocator.alloc(*resolver.StyledNode, 1);
    c_children[0] = &child_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 500, .viewport_height = 600 });

    // Centered vertically in 200px container: (200 - 100) / 2 = 50
    try std.testing.expectEqual(@as(f32, 50), root.children.items[0].dimensions.content.y);
}

test "flex row respects child margins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.width = .{ .value = 500, .unit = .px };

    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.width = .{ .value = 100, .unit = .px };
    child_style.margin_left = .{ .value = 10, .unit = .px };
    child_style.margin_right = .{ .value = 10, .unit = .px };

    var child1_node = resolver.StyledNode{ .node = undefined, .style = child_style, .children = &.{} };
    var child2_node = resolver.StyledNode{ .node = undefined, .style = child_style, .children = &.{} };

    var container_node = resolver.StyledNode{
        .node = undefined,
        .style = container_style,
        .children = &.{},
    };
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child1_node;
    c_children[1] = &child2_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 500, .viewport_height = 600 });

    // Child 1: margin-left 10 -> x = 10. Margin box width = 10 + 100 + 10 = 120
    // Child 2: starts at 120 + margin-left 10 -> x = 130.
    try std.testing.expectEqual(@as(f32, 10), root.children.items[0].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 130), root.children.items[1].dimensions.content.x);
}
