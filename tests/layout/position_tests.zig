const std = @import("std");
const layout = @import("../../src/layout/mod.zig");
const resolver = @import("../../src/css/resolver.zig");
const properties = @import("../../src/css/properties.zig");

test "relative positioning offsets element without affecting siblings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var root = layout.LayoutBox.init(.blockNode, null);

    // Child 1: relative, top: 10, left: 20
    var s1 = properties.ComputedStyle{};
    s1.position = .relative;
    try s1.applyProperty("height", "50px", allocator);
    try s1.applyProperty("top", "10px", allocator);
    try s1.applyProperty("left", "20px", allocator);
    const sn1 = try allocator.create(resolver.StyledNode);
    sn1.* = .{ .node = undefined, .style = s1, .children = &[_]*resolver.StyledNode{} };
    const child1 = try allocator.create(layout.LayoutBox);
    child1.* = layout.LayoutBox.init(.blockNode, sn1);
    child1.parent = &root;

    // Child 2: static
    var s2 = properties.ComputedStyle{};
    try s2.applyProperty("height", "50px", allocator);
    const sn2 = try allocator.create(resolver.StyledNode);
    sn2.* = .{ .node = undefined, .style = s2, .children = &[_]*resolver.StyledNode{} };
    const child2 = try allocator.create(layout.LayoutBox);
    child2.* = layout.LayoutBox.init(.blockNode, sn2);
    child2.parent = &root;

    try root.children.append(allocator, child1);
    try root.children.append(allocator, child2);

    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    // child1 should be offset
    try std.testing.expectEqual(@as(f32, 20), child1.dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 10), child1.dimensions.content.y);

    // child2 should still be at y=50 (ignores child1's relative offset)
    try std.testing.expectEqual(@as(f32, 50), child2.dimensions.content.y);
    try std.testing.expectEqual(@as(f32, 0), child2.dimensions.content.x);

    // root height should still be 100
    try std.testing.expectEqual(@as(f32, 100), root.dimensions.content.height);
}

test "absolute positioning relative to positioned parent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parent: relative, x=100, y=100 (manually set for test)
    var s_parent = properties.ComputedStyle{};
    s_parent.position = .relative;
    try s_parent.applyProperty("width", "200px", allocator);
    try s_parent.applyProperty("height", "200px", allocator);
    const sn_parent = try allocator.create(resolver.StyledNode);
    sn_parent.* = .{ .node = undefined, .style = s_parent, .children = &[_]*resolver.StyledNode{} };
    var parent_box = layout.LayoutBox.init(.blockNode, sn_parent);

    // Child: absolute, top: 10, left: 10
    var s_child = properties.ComputedStyle{};
    s_child.position = .absolute;
    try s_child.applyProperty("width", "50px", allocator);
    try s_child.applyProperty("height", "50px", allocator);
    try s_child.applyProperty("top", "10px", allocator);
    try s_child.applyProperty("left", "10px", allocator);
    const sn_child = try allocator.create(resolver.StyledNode);
    sn_child.* = .{ .node = undefined, .style = s_child, .children = &[_]*resolver.StyledNode{} };
    const child_box = try allocator.create(layout.LayoutBox);
    child_box.* = layout.LayoutBox.init(.blockNode, sn_child);
    child_box.parent = &parent_box;

    try parent_box.children.append(allocator, child_box);

    layout.layoutTree(&parent_box, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    // Absolute child: x = parent.x + left = 0 + 10 = 10
    // y = parent.y + top = 0 + 10 = 10
    try std.testing.expectEqual(@as(f32, 10), child_box.dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 10), child_box.dimensions.content.y);

    // Parent height should be 200 (ignores absolute child)
    try std.testing.expectEqual(@as(f32, 200), parent_box.dimensions.content.height);
}

test "fixed positioning relative to viewport" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var root = layout.LayoutBox.init(.blockNode, null);

    // Fixed child: top: 50, left: 50
    var s_fixed = properties.ComputedStyle{};
    s_fixed.position = .fixed;
    try s_fixed.applyProperty("width", "50px", allocator);
    try s_fixed.applyProperty("height", "50px", allocator);
    try s_fixed.applyProperty("top", "50px", allocator);
    try s_fixed.applyProperty("left", "50px", allocator);
    const sn_fixed = try allocator.create(resolver.StyledNode);
    sn_fixed.* = .{ .node = undefined, .style = s_fixed, .children = &[_]*resolver.StyledNode{} };
    const child_fixed = try allocator.create(layout.LayoutBox);
    child_fixed.* = layout.LayoutBox.init(.blockNode, sn_fixed);
    child_fixed.parent = &root;

    try root.children.append(allocator, child_fixed);

    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    try std.testing.expectEqual(@as(f32, 50), child_fixed.dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 50), child_fixed.dimensions.content.y);

    // Root height should be 0 (only has fixed child)
    try std.testing.expectEqual(@as(f32, 0), root.dimensions.content.height);
}
