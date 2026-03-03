const std = @import("std");
const layout_box = @import("../../src/layout/box.zig");
const dom = @import("../../src/dom/mod.zig");
const hit_test = @import("../../src/render/hit_test.zig");

test "hit test on empty tree (point inside)" {
    const allocator = std.testing.allocator;
    var root = layout_box.LayoutBox.init(.blockNode, null);
    defer root.deinit(allocator);
    root.dimensions.content = .{ .x = 10, .y = 10, .width = 100, .height = 100 };

    const result = hit_test.hitTest(&root, 50, 50, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(&root, result.?.box);
}

test "hit test misses entirely" {
    const allocator = std.testing.allocator;
    var root = layout_box.LayoutBox.init(.blockNode, null);
    defer root.deinit(allocator);
    root.dimensions.content = .{ .x = 10, .y = 10, .width = 100, .height = 100 };

    const result = hit_test.hitTest(&root, 5, 5, 0);
    try std.testing.expect(result == null);
}

test "hit test with nested children" {
    const allocator = std.testing.allocator;
    var root = layout_box.LayoutBox.init(.blockNode, null);
    defer root.deinit(allocator);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 200, .height = 200 };

    var child = try allocator.create(layout_box.LayoutBox);
    child.* = layout_box.LayoutBox.init(.blockNode, null);
    child.dimensions.content = .{ .x = 50, .y = 50, .width = 50, .height = 50 };
    try root.children.append(allocator, child);

    const result = hit_test.hitTest(&root, 75, 75, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(child, result.?.box);
}

test "hit test with overlapping siblings (reverse paint order)" {
    const allocator = std.testing.allocator;
    var root = layout_box.LayoutBox.init(.blockNode, null);
    defer root.deinit(allocator);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 200, .height = 200 };

    // First child
    var child1 = try allocator.create(layout_box.LayoutBox);
    child1.* = layout_box.LayoutBox.init(.blockNode, null);
    child1.dimensions.content = .{ .x = 50, .y = 50, .width = 100, .height = 100 };
    try root.children.append(allocator, child1);

    // Second child (overlaps first, later in DOM = higher in paint order)
    var child2 = try allocator.create(layout_box.LayoutBox);
    child2.* = layout_box.LayoutBox.init(.blockNode, null);
    child2.dimensions.content = .{ .x = 75, .y = 75, .width = 100, .height = 100 };
    try root.children.append(allocator, child2);

    // Point in overlap (75, 75) to (150, 150)
    const result = hit_test.hitTest(&root, 100, 100, 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(child2, result.?.box);
}

test "hit test with scroll offset" {
    const allocator = std.testing.allocator;
    var root = layout_box.LayoutBox.init(.blockNode, null);
    defer root.deinit(allocator);
    root.dimensions.content = .{ .x = 0, .y = 100, .width = 100, .height = 100 };

    // Screen point (50, 50) + scroll (100) = Document point (50, 150) -> Hits root
    const result = hit_test.hitTest(&root, 50, 50, 100);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(&root, result.?.box);
}

test "containsPoint edge cases" {
    const Rect = layout_box.Rect;
    const rect = Rect{ .x = 10, .y = 10, .width = 10, .height = 10 };

    // Using a dummy hitTest call or making it pub and calling it directly
    // Let's assume we can't easily call internal helper, so we test via hitTest
    var root = layout_box.LayoutBox.init(.blockNode, null);
    root.dimensions.content = rect;

    try std.testing.expect(hit_test.hitTest(&root, 10, 10, 0) != null); // Top-left
    try std.testing.expect(hit_test.hitTest(&root, 19, 19, 0) != null); // Bottom-right inside
    try std.testing.expect(hit_test.hitTest(&root, 20, 10, 0) == null); // Right edge (exclusive)
    try std.testing.expect(hit_test.hitTest(&root, 10, 20, 0) == null); // Bottom edge (exclusive)
}
