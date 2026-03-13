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
    try std.testing.expectEqual(@as(f32, 32.0), box2.dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 0.0), box2.dimensions.content.y);

    try std.testing.expectEqual(@as(f32, 19.2), anon.dimensions.content.height);
    try std.testing.expectEqual(@as(f32, 19.2), root.dimensions.content.height);
}

test "inline-block shrink-to-fit auto width" {
    // An inline-block with auto width should shrink to fit its content,
    // not fill the container (CSS 2.1 §10.3.5).
    const allocator = std.testing.allocator;

    // Container block div
    var container_node = dom.Node.init(allocator, .element);
    container_node.tag = .div;

    // Inline-block div
    var ib_node = dom.Node.init(allocator, .element);
    ib_node.tag = .div;

    // Child block with explicit 200px width inside inline-block
    var child_node = dom.Node.init(allocator, .element);
    child_node.tag = .div;

    const limits = dom.Limits{ .max_children = 100, .max_depth = 10, .max_total_nodes = 1000 };
    try ib_node.appendChild(&child_node, limits);
    try container_node.appendChild(&ib_node, limits);

    var container_style = css.ComputedStyle{};
    container_style.display = .block;

    var ib_style = css.ComputedStyle{};
    ib_style.display = .inline_block;
    // width is null (auto) — no explicit width set

    var child_style = css.ComputedStyle{};
    child_style.display = .block;
    child_style.width = .{ .value = 200, .unit = .px };
    child_style.height = .{ .value = 50, .unit = .px };

    var sn_child = css.StyledNode{ .node = &child_node, .style = child_style, .children = &[_]*css.StyledNode{} };
    const ib_children = [_]*css.StyledNode{&sn_child};
    var sn_ib = css.StyledNode{ .node = &ib_node, .style = ib_style, .children = &ib_children };
    const container_children = [_]*css.StyledNode{&sn_ib};
    var sn_container = css.StyledNode{ .node = &container_node, .style = container_style, .children = &container_children };

    const root = try layout.buildLayoutTree(allocator, &sn_container);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        container_node.children.deinit(allocator);
        ib_node.children.deinit(allocator);
        child_node.children.deinit(allocator);
        container_node.attributes.deinit(allocator);
        ib_node.attributes.deinit(allocator);
        child_node.attributes.deinit(allocator);
    }

    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1000.0, .viewport_height = 600.0 });

    // The root is the container block. Inside is an anonymous block wrapping the inline-block.
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
    const anon = root.children.items[0];
    try std.testing.expectEqual(layout.BoxType.anonymousBlock, anon.box_type);

    // The anonymous block contains the inline-block
    try std.testing.expectEqual(@as(usize, 1), anon.children.items.len);
    const ib_box = anon.children.items[0];
    try std.testing.expectEqual(layout.BoxType.inlineBlockNode, ib_box.box_type);

    // The inline-block should shrink to fit its content (200px), NOT fill the 1000px container
    try std.testing.expect(ib_box.dimensions.content.width <= 200.0);
    try std.testing.expect(ib_box.dimensions.content.width > 0.0);
}

test "inline-block with explicit width stays fixed" {
    // An inline-block with an explicit width should NOT shrink-to-fit.
    const allocator = std.testing.allocator;

    var container_node = dom.Node.init(allocator, .element);
    container_node.tag = .div;

    var ib_node = dom.Node.init(allocator, .element);
    ib_node.tag = .div;

    var child_node = dom.Node.init(allocator, .element);
    child_node.tag = .div;

    const limits = dom.Limits{ .max_children = 100, .max_depth = 10, .max_total_nodes = 1000 };
    try ib_node.appendChild(&child_node, limits);
    try container_node.appendChild(&ib_node, limits);

    var container_style = css.ComputedStyle{};
    container_style.display = .block;

    var ib_style = css.ComputedStyle{};
    ib_style.display = .inline_block;
    ib_style.width = .{ .value = 300, .unit = .px }; // explicit width

    var child_style = css.ComputedStyle{};
    child_style.display = .block;
    child_style.width = .{ .value = 100, .unit = .px };
    child_style.height = .{ .value = 50, .unit = .px };

    var sn_child = css.StyledNode{ .node = &child_node, .style = child_style, .children = &[_]*css.StyledNode{} };
    const ib_children = [_]*css.StyledNode{&sn_child};
    var sn_ib = css.StyledNode{ .node = &ib_node, .style = ib_style, .children = &ib_children };
    const container_children = [_]*css.StyledNode{&sn_ib};
    var sn_container = css.StyledNode{ .node = &container_node, .style = container_style, .children = &container_children };

    const root = try layout.buildLayoutTree(allocator, &sn_container);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        container_node.children.deinit(allocator);
        ib_node.children.deinit(allocator);
        child_node.children.deinit(allocator);
        container_node.attributes.deinit(allocator);
        ib_node.attributes.deinit(allocator);
        child_node.attributes.deinit(allocator);
    }

    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1000.0, .viewport_height = 600.0 });

    const anon = root.children.items[0];
    const ib_box = anon.children.items[0];

    // The inline-block has explicit width=300px, so it should stay at 300px
    try std.testing.expectEqual(@as(f32, 300.0), ib_box.dimensions.content.width);
}

test "inline-block shrink-to-fit respects min-width" {
    // An inline-block with auto width and min-width should not shrink below min-width.
    const allocator = std.testing.allocator;

    var container_node = dom.Node.init(allocator, .element);
    container_node.tag = .div;

    var ib_node = dom.Node.init(allocator, .element);
    ib_node.tag = .div;

    var child_node = dom.Node.init(allocator, .element);
    child_node.tag = .div;

    const limits = dom.Limits{ .max_children = 100, .max_depth = 10, .max_total_nodes = 1000 };
    try ib_node.appendChild(&child_node, limits);
    try container_node.appendChild(&ib_node, limits);

    var container_style = css.ComputedStyle{};
    container_style.display = .block;

    var ib_style = css.ComputedStyle{};
    ib_style.display = .inline_block;
    // width is null (auto)
    ib_style.min_width = .{ .value = 250, .unit = .px }; // min-width: 250px

    var child_style = css.ComputedStyle{};
    child_style.display = .block;
    child_style.width = .{ .value = 100, .unit = .px }; // content only 100px
    child_style.height = .{ .value = 50, .unit = .px };

    var sn_child = css.StyledNode{ .node = &child_node, .style = child_style, .children = &[_]*css.StyledNode{} };
    const ib_children = [_]*css.StyledNode{&sn_child};
    var sn_ib = css.StyledNode{ .node = &ib_node, .style = ib_style, .children = &ib_children };
    const container_children = [_]*css.StyledNode{&sn_ib};
    var sn_container = css.StyledNode{ .node = &container_node, .style = container_style, .children = &container_children };

    const root = try layout.buildLayoutTree(allocator, &sn_container);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        container_node.children.deinit(allocator);
        ib_node.children.deinit(allocator);
        child_node.children.deinit(allocator);
        container_node.attributes.deinit(allocator);
        ib_node.attributes.deinit(allocator);
        child_node.attributes.deinit(allocator);
    }

    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1000.0, .viewport_height = 600.0 });

    const anon = root.children.items[0];
    const ib_box = anon.children.items[0];

    // Content is 100px but min-width is 250px, so width should be >= 250px
    try std.testing.expect(ib_box.dimensions.content.width >= 250.0);
}

test "inline-block establishes new BFC isolating inner floats from outer" {
    // CSS 2.1 §9.4.1: inline-block elements establish a new block formatting context.
    // Floats inside an inline-block must NOT leak into the outer float context
    // and must NOT be affected by outer floats.
    //
    // Structure (all within a single container, 600px):
    //   container (block, 600px wide)
    //     child_A: block (100px tall) — pushes subsequent content to y=100
    //     child_B: block containing inline content:
    //       inline-block (300px wide)
    //         inner_float (float:left, 500px wide, 200px tall)
    //     child_C: block (50px tall) — should NOT be pushed down by inner_float
    //
    // If BFC is NOT isolated, inner_float registers in the outer FloatContext.
    // child_C then sees a 500px-wide left float and gets narrowed/shifted.
    // With proper BFC isolation, child_C is unaffected by inner_float.
    //
    // We test: child_C.x == 0 (no float narrowing from inner_float leaking out).
    const allocator = std.testing.allocator;

    // --- DOM nodes ---
    var container_node = dom.Node.init(allocator, .element);
    container_node.tag = .div;

    var child_a_node = dom.Node.init(allocator, .element);
    child_a_node.tag = .div;

    var ib_node = dom.Node.init(allocator, .element);
    ib_node.tag = .div;

    var inner_float_node = dom.Node.init(allocator, .element);
    inner_float_node.tag = .div;

    var child_c_node = dom.Node.init(allocator, .element);
    child_c_node.tag = .div;

    const limits = dom.Limits{ .max_children = 100, .max_depth = 10, .max_total_nodes = 1000 };
    try ib_node.appendChild(&inner_float_node, limits);
    try container_node.appendChild(&child_a_node, limits);
    try container_node.appendChild(&ib_node, limits);
    try container_node.appendChild(&child_c_node, limits);

    // --- Styles ---
    var container_style = css.ComputedStyle{};
    container_style.display = .block;

    // child_A: block, 100px tall
    var child_a_style = css.ComputedStyle{};
    child_a_style.display = .block;
    child_a_style.height = .{ .value = 100, .unit = .px };

    // Inline-block: 300px wide
    var ib_style = css.ComputedStyle{};
    ib_style.display = .inline_block;
    ib_style.width = .{ .value = 300, .unit = .px };

    // Inner float: float:left, 500px wide, 200px tall
    // Deliberately wide so it would cause visible narrowing if it leaked.
    var inner_float_style = css.ComputedStyle{};
    inner_float_style.display = .block;
    inner_float_style.float = .left;
    inner_float_style.width = .{ .value = 500, .unit = .px };
    inner_float_style.height = .{ .value = 200, .unit = .px };

    // child_C: block, 50px tall — should be unaffected by inner_float
    var child_c_style = css.ComputedStyle{};
    child_c_style.display = .block;
    child_c_style.height = .{ .value = 50, .unit = .px };

    // --- Styled tree ---
    var sn_inner_float = css.StyledNode{
        .node = &inner_float_node,
        .style = inner_float_style,
        .children = &[_]*css.StyledNode{},
    };

    var sn_child_a = css.StyledNode{
        .node = &child_a_node,
        .style = child_a_style,
        .children = &[_]*css.StyledNode{},
    };

    const ib_children = [_]*css.StyledNode{&sn_inner_float};
    var sn_ib = css.StyledNode{
        .node = &ib_node,
        .style = ib_style,
        .children = &ib_children,
    };

    var sn_child_c = css.StyledNode{
        .node = &child_c_node,
        .style = child_c_style,
        .children = &[_]*css.StyledNode{},
    };

    const container_children = [_]*css.StyledNode{ &sn_child_a, &sn_ib, &sn_child_c };
    var sn_container = css.StyledNode{
        .node = &container_node,
        .style = container_style,
        .children = &container_children,
    };

    const root = try layout.buildLayoutTree(allocator, &sn_container);
    defer {
        root.deinit(allocator);
        allocator.destroy(root);
        container_node.children.deinit(allocator);
        child_a_node.children.deinit(allocator);
        ib_node.children.deinit(allocator);
        inner_float_node.children.deinit(allocator);
        child_c_node.children.deinit(allocator);
        container_node.attributes.deinit(allocator);
        child_a_node.attributes.deinit(allocator);
        ib_node.attributes.deinit(allocator);
        inner_float_node.attributes.deinit(allocator);
        child_c_node.attributes.deinit(allocator);
    }

    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 600.0, .viewport_height = 600.0 });

    // Find child_C — the last block child of root.
    // The tree structure is:
    //   root
    //     child_A (blockNode)
    //     anonymousBlock (wrapping inline-block)
    //       inlineBlockNode
    //         inner_float (blockNode, float:left)
    //     child_C (blockNode)
    var child_c_box: ?*layout.LayoutBox = null;
    const num_children = root.children.items.len;
    if (num_children > 0) {
        const last = root.children.items[num_children - 1];
        if (last.box_type == .blockNode) {
            if (last.styled_node) |sn| {
                if (sn.style.height != null and sn.style.height.?.value == 50) {
                    child_c_box = last;
                }
            }
        }
    }

    try std.testing.expect(child_c_box != null);
    const child_c = child_c_box.?;

    // child_C should start at x = root.content.x (no float narrowing).
    // If the inner float leaked into the outer FloatContext, child_C
    // would be shifted right by 500px (the leaked left float width).
    const child_c_offset_x = child_c.dimensions.content.x - root.dimensions.content.x;
    try std.testing.expectEqual(@as(f32, 0.0), child_c_offset_x);
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
