const std = @import("std");
const dom = @import("../../src/dom/mod.zig");
const css = @import("../../src/css/mod.zig");
const layout = @import("../../src/layout/mod.zig");

const limits = dom.Limits{ .max_children = 100, .max_depth = 10, .max_total_nodes = 1000 };

fn makeTextNode(allocator: std.mem.Allocator, text: []const u8) dom.Node {
    var node = dom.Node.init(allocator, .text);
    node.data = text;
    return node;
}

fn deinitNode(node: *dom.Node) void {
    node.children.deinit(node.allocator);
    node.attributes.deinit(node.allocator);
}

fn makeStyledInline(node: *const dom.Node) css.StyledNode {
    var style = css.ComputedStyle{};
    style.display = .inline_val;
    return css.StyledNode{
        .node = node,
        .style = style,
        .children = &[_]*css.StyledNode{},
    };
}

test "word wrap within single text node" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .div;

    // "hello world" = 11 chars * 8 = 88px total
    // "hello" = 5*8=40, "world" = 5*8=40
    // Container is 60px wide: "hello" fits (40 <= 60), then space advances to 48,
    // "world" at 48+40=88 > 60, so wraps to next line.
    var text_node = makeTextNode(allocator, "hello world");
    try parent_node.appendChild(&text_node, limits);

    var style = css.ComputedStyle{};
    style.display = .block;

    var sn_text = makeStyledInline(&text_node);
    const sn_children = [_]*css.StyledNode{&sn_text};
    var sn_parent = css.StyledNode{
        .node = &parent_node,
        .style = style,
        .children = &sn_children,
    };

    const root = try layout.buildLayoutTree(allocator, &sn_parent);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        deinitNode(&parent_node);
        deinitNode(&text_node);
    }

    layout.layoutTree(root, .{
        .allocator = allocator,
        .viewport_width = 60.0,
        .viewport_height = 600.0,
    });

    const anon = root.children.items[0];
    // Parent height should be 2 lines = 38.4px
    try std.testing.expectEqual(@as(f32, 38.4), anon.dimensions.content.height);
    try std.testing.expectEqual(@as(f32, 38.4), root.dimensions.content.height);
}

test "no wrap when text fits on one line" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .div;

    // "hi there" = 8 chars * 8 = 64px total
    // "hi"=16, space=8, "there"=40 => fits in 200px
    var text_node = makeTextNode(allocator, "hi there");
    try parent_node.appendChild(&text_node, limits);

    var style = css.ComputedStyle{};
    style.display = .block;

    var sn_text = makeStyledInline(&text_node);
    const sn_children = [_]*css.StyledNode{&sn_text};
    var sn_parent = css.StyledNode{
        .node = &parent_node,
        .style = style,
        .children = &sn_children,
    };

    const root = try layout.buildLayoutTree(allocator, &sn_parent);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        deinitNode(&parent_node);
        deinitNode(&text_node);
    }

    layout.layoutTree(root, .{
        .allocator = allocator,
        .viewport_width = 200.0,
        .viewport_height = 600.0,
    });

    const anon = root.children.items[0];
    try std.testing.expectEqual(@as(f32, 19.2), anon.dimensions.content.height);
    try std.testing.expectEqual(@as(f32, 19.2), root.dimensions.content.height);
}

test "empty text node gets zero width" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .div;

    var text_node = makeTextNode(allocator, "");
    try parent_node.appendChild(&text_node, limits);

    var style = css.ComputedStyle{};
    style.display = .block;

    var sn_text = makeStyledInline(&text_node);
    const sn_children = [_]*css.StyledNode{&sn_text};
    var sn_parent = css.StyledNode{
        .node = &parent_node,
        .style = style,
        .children = &sn_children,
    };

    const root = try layout.buildLayoutTree(allocator, &sn_parent);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        deinitNode(&parent_node);
        deinitNode(&text_node);
    }

    layout.layoutTree(root, .{
        .allocator = allocator,
        .viewport_width = 100.0,
        .viewport_height = 600.0,
    });

    try std.testing.expectEqual(@as(usize, 0), root.children.items.len);
}

test "multiple words wrap across several lines" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .div;

    // "aa bb cc dd" has words: aa(16), bb(16), cc(16), dd(16)
    // Container width = 40px
    // Line 1: "aa" (16), +space(8)+bb(16)=40 fits => cursor_x=40
    // Line 2: "cc" needs 8+16=24 from 40 => 40+24>40, wrap. cc(16) cursor_x=16, +space(8)+dd(16)=40 fits
    // So 2 lines => height = 38.4
    var text_node = makeTextNode(allocator, "aa bb cc dd");
    try parent_node.appendChild(&text_node, limits);

    var style = css.ComputedStyle{};
    style.display = .block;

    var sn_text = makeStyledInline(&text_node);
    const sn_children = [_]*css.StyledNode{&sn_text};
    var sn_parent = css.StyledNode{
        .node = &parent_node,
        .style = style,
        .children = &sn_children,
    };

    const root = try layout.buildLayoutTree(allocator, &sn_parent);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        deinitNode(&parent_node);
        deinitNode(&text_node);
    }

    layout.layoutTree(root, .{
        .allocator = allocator,
        .viewport_width = 40.0,
        .viewport_height = 600.0,
    });

    const anon = root.children.items[0];
    try std.testing.expectEqual(@as(f32, 38.4), anon.dimensions.content.height);
}

test "word wrap with multiple text nodes" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .div;

    // First text: "hello world" in 60px container
    // "hello"(40) fits, space(8)+world(40)=48, 40+48>60 => wrap
    // After first text: cursor_x=40, cursor_y=19.2
    // Second text: "foo" = 24px
    // cursor_x(40)+24=64 > 60 => wrap again. cursor_y=38.4, cursor_x=24
    // Total: 3 lines = 57.6px
    var text1_node = makeTextNode(allocator, "hello world");
    var text2_node = makeTextNode(allocator, "foo");
    try parent_node.appendChild(&text1_node, limits);
    try parent_node.appendChild(&text2_node, limits);

    var style = css.ComputedStyle{};
    style.display = .block;

    var sn1 = makeStyledInline(&text1_node);
    var sn2 = makeStyledInline(&text2_node);
    const sn_children = [_]*css.StyledNode{ &sn1, &sn2 };
    var sn_parent = css.StyledNode{
        .node = &parent_node,
        .style = style,
        .children = &sn_children,
    };

    const root = try layout.buildLayoutTree(allocator, &sn_parent);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        deinitNode(&parent_node);
        deinitNode(&text1_node);
        deinitNode(&text2_node);
    }

    layout.layoutTree(root, .{
        .allocator = allocator,
        .viewport_width = 60.0,
        .viewport_height = 600.0,
    });

    const anon = root.children.items[0];
    try std.testing.expectApproxEqAbs(@as(f32, 57.6), anon.dimensions.content.height, 0.001);
}

test "single word no wrap" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .div;

    // "ABC" = 3*8=24px, no spaces, no wrapping needed in 100px container
    var text_node = makeTextNode(allocator, "ABC");
    try parent_node.appendChild(&text_node, limits);

    var style = css.ComputedStyle{};
    style.display = .block;

    var sn_text = makeStyledInline(&text_node);
    const sn_children = [_]*css.StyledNode{&sn_text};
    var sn_parent = css.StyledNode{
        .node = &parent_node,
        .style = style,
        .children = &sn_children,
    };

    const root = try layout.buildLayoutTree(allocator, &sn_parent);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        deinitNode(&parent_node);
        deinitNode(&text_node);
    }

    layout.layoutTree(root, .{
        .allocator = allocator,
        .viewport_width = 100.0,
        .viewport_height = 600.0,
    });

    const anon = root.children.items[0];
    const child = anon.children.items[0];
    // half-leading = (19.2 - 16) / 2 = 1.6 for default styles
    try std.testing.expectEqual(@as(f32, 24.0), child.dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 0.0), child.dimensions.content.x);
    try std.testing.expectApproxEqAbs(@as(f32, 1.6), child.dimensions.content.y, 0.01);
    try std.testing.expectEqual(@as(f32, 19.2), anon.dimensions.content.height);
}

test "wrapped text child width capped at container width" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .div;

    // "hello world" = 11 chars * 8 = 88px total
    // Container width = 60px
    // Text should wrap.
    // BUG-F: Child width would be 88 (too large).
    // Fix: Child width should be 60.
    var text_node = makeTextNode(allocator, "hello world");
    try parent_node.appendChild(&text_node, limits);

    var style = css.ComputedStyle{};
    style.display = .block;

    var sn_text = makeStyledInline(&text_node);
    const sn_children = [_]*css.StyledNode{&sn_text};
    var sn_parent = css.StyledNode{
        .node = &parent_node,
        .style = style,
        .children = &sn_children,
    };

    const root = try layout.buildLayoutTree(allocator, &sn_parent);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        deinitNode(&parent_node);
        deinitNode(&text_node);
    }

    layout.layoutTree(root, .{
        .allocator = allocator,
        .viewport_width = 60.0,
        .viewport_height = 600.0,
    });

    const anon = root.children.items[0];
    const child = anon.children.items[0];
    try std.testing.expectEqual(@as(f32, 40.0), child.dimensions.content.width);
}
