const std = @import("std");
const layout = @import("../../src/layout/mod.zig");
const properties = @import("../../src/css/properties.zig");
const resolver = @import("../../src/css/resolver.zig");

fn makeChild(allocator: std.mem.Allocator, height: []const u8, mb: []const u8, mt: []const u8) !*layout.LayoutBox {
    var style = properties.ComputedStyle{};
    try style.applyProperty("height", height, allocator);
    if (mb.len > 0) try style.applyProperty("margin-bottom", mb, allocator);
    if (mt.len > 0) try style.applyProperty("margin-top", mt, allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = undefined, .style = style, .children = &[_]*resolver.StyledNode{} };
    const child = try allocator.create(layout.LayoutBox);
    child.* = layout.LayoutBox.init(.blockNode, sn);
    return child;
}

fn doLayout(root: *layout.LayoutBox, allocator: std.mem.Allocator) void {
    layout.layoutTree(root, .{
        .allocator = allocator,
        .viewport_width = 500,
        .viewport_height = 600,
    });
}

test "margin collapsing: adjacent siblings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var root = layout.LayoutBox.init(.blockNode, null);
    const c1 = try makeChild(alloc, "50px", "20px", "");
    const c2 = try makeChild(alloc, "50px", "", "30px");
    try root.children.append(alloc, c1);
    try root.children.append(alloc, c2);

    doLayout(&root, alloc);

    // c1 marginBox = 0 + 50 + 20 = 70
    // c2 marginBox = 30 + 50 + 0 = 80
    // Without collapse: 150. Overlap = 20 + 30 - max(20,30) = 20.
    // With collapse: 130.
    try std.testing.expectEqual(@as(f32, 130), root.dimensions.content.height);

    // c2 y should be shifted up by the overlap of 20
    // Without collapse c2.y = 0 + 70 (c1 margin box) + 30 (c2 margin top) = 100
    // With collapse c2.y = 100 - 20 = 80
    try std.testing.expectEqual(@as(f32, 80), c2.dimensions.content.y);
}

test "margin collapsing: equal margins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var root = layout.LayoutBox.init(.blockNode, null);
    const c1 = try makeChild(alloc, "40px", "15px", "");
    const c2 = try makeChild(alloc, "40px", "", "15px");
    try root.children.append(alloc, c1);
    try root.children.append(alloc, c2);

    doLayout(&root, alloc);

    // c1 marginBox = 0 + 40 + 15 = 55
    // c2 marginBox = 15 + 40 + 0 = 55
    // Overlap = 15 + 15 - max(15,15) = 15
    // Height = 110 - 15 = 95
    try std.testing.expectEqual(@as(f32, 95), root.dimensions.content.height);
}

test "margin collapsing: no collapse for single child" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var root = layout.LayoutBox.init(.blockNode, null);
    const c1 = try makeChild(alloc, "50px", "10px", "20px");
    try root.children.append(alloc, c1);

    doLayout(&root, alloc);

    // Single child: no sibling collapsing. marginBox = 20 + 50 + 10 = 80
    try std.testing.expectEqual(@as(f32, 80), root.dimensions.content.height);
    try std.testing.expectEqual(@as(f32, 20), c1.dimensions.content.y);
}

test "margin collapsing: three siblings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var root = layout.LayoutBox.init(.blockNode, null);

    // c1: height=50, mt=0, mb=20
    const c1 = try makeChild(alloc, "50px", "20px", "");
    // c2: height=50, mt=10, mb=30
    var s2 = properties.ComputedStyle{};
    try s2.applyProperty("height", "50px", alloc);
    try s2.applyProperty("margin-top", "10px", alloc);
    try s2.applyProperty("margin-bottom", "30px", alloc);
    const sn2 = try alloc.create(resolver.StyledNode);
    sn2.* = .{ .node = undefined, .style = s2, .children = &[_]*resolver.StyledNode{} };
    const c2 = try alloc.create(layout.LayoutBox);
    c2.* = layout.LayoutBox.init(.blockNode, sn2);
    // c3: height=50, mt=15, mb=0
    const c3 = try makeChild(alloc, "50px", "", "15px");

    try root.children.append(alloc, c1);
    try root.children.append(alloc, c2);
    try root.children.append(alloc, c3);

    doLayout(&root, alloc);

    // c1 marginBox = 0+50+20 = 70
    // c2 marginBox = 10+50+30 = 90
    // c3 marginBox = 15+50+0 = 65
    // Without collapse: 225
    // Collapse c1-c2: overlap = 20+10-max(20,10) = 10
    // Collapse c2-c3: overlap = 30+15-max(30,15) = 15
    // With collapse: 225 - 10 - 15 = 200
    try std.testing.expectEqual(@as(f32, 200), root.dimensions.content.height);
}
