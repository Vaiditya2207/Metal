const std = @import("std");
const dom = @import("../../src/dom/mod.zig");
const css = @import("../../src/css/mod.zig");
const layout = @import("../../src/layout/mod.zig");

test "inline layout side-by-side" {
    const allocator = std.testing.allocator;

    // Create a parent block with 100px width
    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .div;

    var text1_node = dom.Node.init(allocator, .text);
    text1_node.data = "ABC"; // 3 * 8 = 24px

    var text2_node = dom.Node.init(allocator, .text);
    text2_node.data = "DEFG"; // 4 * 8 = 32px

    const limits = dom.Limits{ .max_children = 100, .max_depth = 10, .max_total_nodes = 1000 };
    try parent_node.appendChild(&text1_node, limits);
    try parent_node.appendChild(&text2_node, limits);

    var style = css.ComputedStyle{};
    style.display = .block;

    var t1_style = css.ComputedStyle{};
    t1_style.display = .inline_val;

    var t2_style = css.ComputedStyle{};
    t2_style.display = .inline_val;

    var sn1 = css.StyledNode{ .node = &text1_node, .style = t1_style, .children = &[_]*css.StyledNode{} };
    var sn2 = css.StyledNode{ .node = &text2_node, .style = t2_style, .children = &[_]*css.StyledNode{} };
    const sn_children = [_]*css.StyledNode{ &sn1, &sn2 };
    var sn_parent = css.StyledNode{ .node = &parent_node, .style = style, .children = &sn_children };

    const root = try layout.buildLayoutTree(allocator, &sn_parent);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        parent_node.children.deinit(allocator);
        text1_node.children.deinit(allocator);
        text2_node.children.deinit(allocator);
        parent_node.attributes.deinit(allocator);
        text1_node.attributes.deinit(allocator);
        text2_node.attributes.deinit(allocator);
    }

    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 100.0, .viewport_height = 600.0 });

    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
    const anon = root.children.items[0];
    try std.testing.expectEqual(layout.BoxType.anonymousBlock, anon.box_type);

    try std.testing.expectEqual(@as(usize, 2), anon.children.items.len);
    const box1 = anon.children.items[0];
    const box2 = anon.children.items[1];

    try std.testing.expectEqual(@as(f32, 24.0), box1.dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 0.0), box1.dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 0.0), box1.dimensions.content.y);

    try std.testing.expectEqual(@as(f32, 32.0), box2.dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 24.0), box2.dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 0.0), box2.dimensions.content.y);

    try std.testing.expectEqual(@as(f32, 19.2), anon.dimensions.content.height);
    try std.testing.expectEqual(@as(f32, 19.2), root.dimensions.content.height);
}

test "inline layout wrap" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .div;

    var text1_node = dom.Node.init(allocator, .text);
    text1_node.data = "ABC"; // 24px

    var text2_node = dom.Node.init(allocator, .text);
    text2_node.data = "DEFG"; // 32px

    const limits = dom.Limits{ .max_children = 100, .max_depth = 10, .max_total_nodes = 1000 };
    try parent_node.appendChild(&text1_node, limits);
    try parent_node.appendChild(&text2_node, limits);

    var style = css.ComputedStyle{};
    style.display = .block;

    var t1_style = css.ComputedStyle{};
    t1_style.display = .inline_val;

    var t2_style = css.ComputedStyle{};
    t2_style.display = .inline_val;

    var sn1 = css.StyledNode{ .node = &text1_node, .style = t1_style, .children = &[_]*css.StyledNode{} };
    var sn2 = css.StyledNode{ .node = &text2_node, .style = t2_style, .children = &[_]*css.StyledNode{} };
    const sn_children = [_]*css.StyledNode{ &sn1, &sn2 };
    var sn_parent = css.StyledNode{ .node = &parent_node, .style = style, .children = &sn_children };

    const root = try layout.buildLayoutTree(allocator, &sn_parent);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        parent_node.children.deinit(allocator);
        text1_node.children.deinit(allocator);
        text2_node.children.deinit(allocator);
        parent_node.attributes.deinit(allocator);
        text1_node.attributes.deinit(allocator);
        text2_node.attributes.deinit(allocator);
    }

    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 40.0, .viewport_height = 600.0 });

    const anon = root.children.items[0];
    const box1 = anon.children.items[0];
    const box2 = anon.children.items[1];

    try std.testing.expectEqual(@as(f32, 24.0), box1.dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 0.0), box1.dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 0.0), box1.dimensions.content.y);

    try std.testing.expectEqual(@as(f32, 32.0), box2.dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 0.0), box2.dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 19.2), box2.dimensions.content.y);

    try std.testing.expectEqual(@as(f32, 38.4), anon.dimensions.content.height);
    try std.testing.expectEqual(@as(f32, 38.4), root.dimensions.content.height);
}
