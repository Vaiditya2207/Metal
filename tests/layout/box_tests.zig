const std = @import("std");
const layout = @import("../../src/layout/mod.zig");
const resolver = @import("../../src/css/resolver.zig");
const dom = @import("../../src/dom/mod.zig");
const properties = @import("../../src/css/properties.zig");

fn createTestStyledNode(allocator: std.mem.Allocator, node_type: dom.NodeType, display: properties.Display) !*resolver.StyledNode {
    const node = try allocator.create(dom.Node);
    node.* = dom.Node.init(allocator, node_type);
    if (node_type == .text) {
        node.data = try allocator.dupe(u8, "test text");
    }

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{
        .node = node,
        .style = .{ .display = display },
        .children = &.{},
    };
    return sn;
}

fn setChildren(allocator: std.mem.Allocator, parent: *resolver.StyledNode, children: []const *resolver.StyledNode) !void {
    const slice = try allocator.alloc(*resolver.StyledNode, children.len);
    @memcpy(slice, children);
    parent.children = slice;
}

test "layout tree basic block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sn = try createTestStyledNode(allocator, .element, .block);
    const root = try layout.buildLayoutTree(allocator, sn);

    try std.testing.expectEqual(layout.BoxType.blockNode, root.box_type);
    try std.testing.expectEqual(sn, root.styled_node.?);
}

test "layout tree skip display none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const parent_sn = try createTestStyledNode(allocator, .element, .block);
    const child_sn = try createTestStyledNode(allocator, .element, .none);

    try setChildren(allocator, parent_sn, &.{child_sn});

    const root = try layout.buildLayoutTree(allocator, parent_sn);

    try std.testing.expectEqual(layout.BoxType.blockNode, root.box_type);
    try std.testing.expectEqual(@as(usize, 0), root.children.items.len);
}

test "layout tree anonymous block generation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Structure:
    // Block (Parent)
    //   Inline 1
    //   Block 2
    //   Inline 3
    //   Inline 4

    const parent_sn = try createTestStyledNode(allocator, .element, .block);
    const inline1 = try createTestStyledNode(allocator, .text, .inline_val);
    const block2 = try createTestStyledNode(allocator, .element, .block);
    const inline3 = try createTestStyledNode(allocator, .text, .inline_val);
    const inline4 = try createTestStyledNode(allocator, .text, .inline_val);

    try setChildren(allocator, parent_sn, &.{ inline1, block2, inline3, inline4 });

    const root = try layout.buildLayoutTree(allocator, parent_sn);

    // Expected:
    // Block (Parent)
    //   AnonymousBlock
    //     Inline 1
    //   Block 2
    //   AnonymousBlock
    //     Inline 3
    //     Inline 4

    try std.testing.expectEqual(@as(usize, 3), root.children.items.len);

    try std.testing.expectEqual(layout.BoxType.anonymousBlock, root.children.items[0].box_type);
    try std.testing.expectEqual(@as(usize, 1), root.children.items[0].children.items.len);
    try std.testing.expectEqual(inline1, root.children.items[0].children.items[0].styled_node.?);

    try std.testing.expectEqual(layout.BoxType.blockNode, root.children.items[1].box_type);
    try std.testing.expectEqual(block2, root.children.items[1].styled_node.?);

    try std.testing.expectEqual(layout.BoxType.anonymousBlock, root.children.items[2].box_type);
    try std.testing.expectEqual(@as(usize, 2), root.children.items[2].children.items.len);
    try std.testing.expectEqual(inline3, root.children.items[2].children.items[0].styled_node.?);
    try std.testing.expectEqual(inline4, root.children.items[2].children.items[1].styled_node.?);
}

test "dimensions box helper methods" {
    const dim = layout.Dimensions{
        .content = .{ .x = 10, .y = 10, .width = 100, .height = 100 },
        .padding = .{ .top = 5, .right = 5, .bottom = 5, .left = 5 },
        .border = .{ .top = 2, .right = 2, .bottom = 2, .left = 2 },
        .margin = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
    };

    const p_box = dim.paddingBox();
    try std.testing.expectEqual(@as(f32, 5), p_box.x);
    try std.testing.expectEqual(@as(f32, 5), p_box.y);
    try std.testing.expectEqual(@as(f32, 110), p_box.width);
    try std.testing.expectEqual(@as(f32, 110), p_box.height);

    const b_box = dim.borderBox();
    try std.testing.expectEqual(@as(f32, 3), b_box.x);
    try std.testing.expectEqual(@as(f32, 3), b_box.y);
    try std.testing.expectEqual(@as(f32, 114), b_box.width);
    try std.testing.expectEqual(@as(f32, 114), b_box.height);

    const m_box = dim.marginBox();
    try std.testing.expectEqual(@as(f32, -7), m_box.x);
    try std.testing.expectEqual(@as(f32, -7), m_box.y);
    try std.testing.expectEqual(@as(f32, 134), m_box.width);
    try std.testing.expectEqual(@as(f32, 134), m_box.height);
}
