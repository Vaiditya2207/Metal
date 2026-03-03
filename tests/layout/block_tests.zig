const std = @import("std");
const layout = @import("../../src/layout/mod.zig");
const resolver = @import("../../src/css/resolver.zig");
const properties = @import("../../src/css/properties.zig");

test "root takes specified containing block width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var root = layout.LayoutBox.init(.blockNode, null);
    layout.layoutTree(&root, .{ .allocator = arena.allocator(), .viewport_width = 800, .viewport_height = 600 });

    try std.testing.expectEqual(@as(f32, 800), root.dimensions.content.width);
}

test "child block inherits parent width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var root = layout.LayoutBox.init(.blockNode, null);
    const child = try allocator.create(layout.LayoutBox);
    child.* = layout.LayoutBox.init(.blockNode, null);
    try root.children.append(allocator, child);

    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    try std.testing.expectEqual(@as(f32, 800), root.dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 800), child.dimensions.content.width);
}

test "explicit width and height are respected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    try style.applyProperty("width", "100px", allocator);
    try style.applyProperty("height", "50px", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{
        .node = undefined, // Not used in layout logic
        .style = style,
        .children = &[_]*resolver.StyledNode{},
    };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    try std.testing.expectEqual(@as(f32, 100), root.dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 50), root.dimensions.content.height);
}

test "two sibling block boxes are placed vertically" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var root = layout.LayoutBox.init(.blockNode, null);

    var s1 = properties.ComputedStyle{};
    try s1.applyProperty("height", "100px", allocator);
    const sn1 = try allocator.create(resolver.StyledNode);
    sn1.* = .{ .node = undefined, .style = s1, .children = &[_]*resolver.StyledNode{} };
    const child1 = try allocator.create(layout.LayoutBox);
    child1.* = layout.LayoutBox.init(.blockNode, sn1);

    var s2 = properties.ComputedStyle{};
    try s2.applyProperty("height", "200px", allocator);
    const sn2 = try allocator.create(resolver.StyledNode);
    sn2.* = .{ .node = undefined, .style = s2, .children = &[_]*resolver.StyledNode{} };
    const child2 = try allocator.create(layout.LayoutBox);
    child2.* = layout.LayoutBox.init(.blockNode, sn2);

    try root.children.append(allocator, child1);
    try root.children.append(allocator, child2);

    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    try std.testing.expectEqual(@as(f32, 0), child1.dimensions.content.y);
    try std.testing.expectEqual(@as(f32, 100), child2.dimensions.content.y);
    try std.testing.expectEqual(@as(f32, 300), root.dimensions.content.height);
}

test "margins, paddings, and borders affect placement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var root = layout.LayoutBox.init(.blockNode, null);

    var s1 = properties.ComputedStyle{};
    try s1.applyProperty("height", "100px", allocator);
    try s1.applyProperty("margin", "10px", allocator);
    try s1.applyProperty("padding", "5px", allocator);
    try s1.applyProperty("border-width", "2px", allocator);
    const sn1 = try allocator.create(resolver.StyledNode);
    sn1.* = .{ .node = undefined, .style = s1, .children = &[_]*resolver.StyledNode{} };
    const child1 = try allocator.create(layout.LayoutBox);
    child1.* = layout.LayoutBox.init(.blockNode, sn1);

    try root.children.append(allocator, child1);

    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    // x = cb.x + margin-left + border-left + padding-left = 0 + 10 + 2 + 5 = 17
    try std.testing.expectEqual(@as(f32, 17), child1.dimensions.content.x);
    // y = cb.y + margin-top + border-top + padding-top = 0 + 10 + 2 + 5 = 17
    try std.testing.expectEqual(@as(f32, 17), child1.dimensions.content.y);

    // child1 border box width = 100 + 5 + 5 + 2 + 2 = 114 (wait, content width is auto)
    // auto width = 800 - (10+10+5+5+2+2) = 800 - 34 = 766
    try std.testing.expectEqual(@as(f32, 766), child1.dimensions.content.width);

    // Root height should be child1's margin box height = 10 + 2 + 5 + 100 + 5 + 2 + 10 = 134
    try std.testing.expectEqual(@as(f32, 134), root.dimensions.content.height);
}

test "em unit resolves relative to font size" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    try style.applyProperty("width", "10em", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = undefined, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600, .root_font_size = 20.0 });

    try std.testing.expectEqual(@as(f32, 200), root.dimensions.content.width);
}

test "percent unit resolves relative to containing block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties.ComputedStyle{};
    try style.applyProperty("width", "50%", allocator);

    const sn = try allocator.create(resolver.StyledNode);
    sn.* = .{ .node = undefined, .style = style, .children = &[_]*resolver.StyledNode{} };

    var root = layout.LayoutBox.init(.blockNode, sn);
    layout.layoutTree(&root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    try std.testing.expectEqual(@as(f32, 400), root.dimensions.content.width);
}
