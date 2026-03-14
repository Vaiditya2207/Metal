const std = @import("std");
const resolver = @import("../../src/css/resolver.zig");
const properties = @import("../../src/css/properties.zig");
const layout = @import("../../src/layout/mod.zig");
const values = @import("../../src/css/values.zig");
const dom = @import("../../src/dom/mod.zig");
const user_agent = @import("../../src/css/user_agent.zig");

test "flex row with flex-grow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

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
        .node = &dummy_node,
        .style = child1_style,
        .children = &.{},
    };

    // Child 2: flex-grow: 4
    var child2_style = properties.ComputedStyle{};
    child2_style.display = .block;
    child2_style.flex_grow = 4;

    var child2_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child2_style,
        .children = &.{},
    };

    var container_node = resolver.StyledNode{
        .node = &dummy_node, // not used by layout
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
    var dummy_node = dom.Node.init(allocator, .element);

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.justify_content = .space_between;
    container_style.width = .{ .value = 500, .unit = .px };

    // Two children, each 100px wide
    var child1_style = properties.ComputedStyle{};
    child1_style.display = .block;
    child1_style.width = .{ .value = 100, .unit = .px };

    var child1_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child1_style,
        .children = &.{},
    };

    var child2_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child1_style,
        .children = &.{},
    };

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
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 500, .viewport_height = 600 });

    // Child 1 at 0, Child 2 at 400 (500 - 100)
    try std.testing.expectEqual(@as(f32, 0), root.children.items[0].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 400), root.children.items[1].dimensions.content.x);
}

test "flex column" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .column;
    container_style.width = .{ .value = 500, .unit = .px };

    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.height = .{ .value = 50, .unit = .px };

    var child1_node = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };
    var child2_node = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };

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
    var dummy_node = dom.Node.init(allocator, .element);

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.align_items = .center;
    container_style.height = .{ .value = 200, .unit = .px };
    container_style.width = .{ .value = 500, .unit = .px };

    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.height = .{ .value = 100, .unit = .px };
    child_style.width = .{ .value = 100, .unit = .px };

    var child_node = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
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
    var dummy_node = dom.Node.init(allocator, .element);

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.width = .{ .value = 500, .unit = .px };

    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.width = .{ .value = 100, .unit = .px };
    child_style.margin_left = .{ .value = 10, .unit = .px };
    child_style.margin_right = .{ .value = 10, .unit = .px };

    var child1_node = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };
    var child2_node = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };

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
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 500, .viewport_height = 600 });

    // Child 1: margin-left 10 -> x = 10. Margin box width = 10 + 100 + 10 = 120
    // Child 2: starts at 120 + margin-left 10 -> x = 130.
    try std.testing.expectEqual(@as(f32, 10), root.children.items[0].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 130), root.children.items[1].dimensions.content.x);
}

test "flex row container with padding positions children correctly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: 500px wide, padding: 20px, display: flex
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.width = .{ .value = 500, .unit = .px };
    container_style.padding_left = .{ .value = 20, .unit = .px };
    container_style.padding_right = .{ .value = 20, .unit = .px };
    container_style.padding_top = .{ .value = 20, .unit = .px };
    container_style.padding_bottom = .{ .value = 20, .unit = .px };

    // Child: 100px wide, 50px high
    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.width = .{ .value = 100, .unit = .px };
    child_style.height = .{ .value = 50, .unit = .px };

    var grandchild_node = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };
    var child_node = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{&grandchild_node} };

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = &.{&child_node},
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1000, .viewport_height = 1000 });

    // Container: content-box with explicit width=500, so content.width IS 500
    // (padding is added on top, not subtracted from width)
    try std.testing.expectEqual(@as(f32, 500), root.dimensions.content.width);

    // Child 0 x should be 20 (inside padding)
    try std.testing.expectEqual(@as(f32, 20), root.children.items[0].dimensions.content.x);
    // Child 0 y should be 20 (inside padding)
    try std.testing.expectEqual(@as(f32, 20), root.children.items[0].dimensions.content.y);
    // Grandchild should shift with its flex item parent.
    try std.testing.expectEqual(@as(f32, 20), root.children.items[0].children.items[0].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 20), root.children.items[0].children.items[0].dimensions.content.y);

    // Container height should match tallest child (50)
    // BUG-E: Currently fails (returns 0)
    try std.testing.expectEqual(@as(f32, 50), root.dimensions.content.height);
}

test "flex row gap spacing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.width = .{ .value = 400, .unit = .px };
    container_style.column_gap = .{ .value = 20, .unit = .px };

    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.width = .{ .value = 100, .unit = .px };
    child_style.height = .{ .value = 30, .unit = .px };

    var child1 = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };
    var child2 = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };
    var container_node = resolver.StyledNode{ .node = &dummy_node, .style = container_style, .children = &.{} };
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child1;
    c_children[1] = &child2;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 400, .viewport_height = 300 });

    try std.testing.expectEqual(@as(f32, 0), root.children.items[0].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 120), root.children.items[1].dimensions.content.x);
}

test "flex row wrap creates new line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.width = .{ .value = 210, .unit = .px };
    container_style.flex_wrap = .wrap;
    container_style.column_gap = .{ .value = 10, .unit = .px };
    container_style.row_gap = .{ .value = 10, .unit = .px };

    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.width = .{ .value = 100, .unit = .px };
    child_style.height = .{ .value = 40, .unit = .px };

    var child1 = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };
    var child2 = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };
    var child3 = resolver.StyledNode{ .node = &dummy_node, .style = child_style, .children = &.{} };
    var container_node = resolver.StyledNode{ .node = &dummy_node, .style = container_style, .children = &.{} };
    const c_children = try allocator.alloc(*resolver.StyledNode, 3);
    c_children[0] = &child1;
    c_children[1] = &child2;
    c_children[2] = &child3;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 210, .viewport_height = 300 });

    try std.testing.expectEqual(@as(f32, 0), root.children.items[0].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 110), root.children.items[1].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 0), root.children.items[2].dimensions.content.x);
    try std.testing.expectEqual(@as(f32, 50), root.children.items[2].dimensions.content.y);
}

test "RC-3: block parent accumulates flex child height (simple)" {
    // Reproduces the Google.com body height=0 bug — simple variant.
    // Structure: html (root, explicit height) -> body (no height, no padding/border) -> flex column div (explicit height)
    // body should accumulate the flex child's height.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create real DOM nodes with proper parent chain so is_root checks work correctly
    var html_dom = dom.Node.init(allocator, .element);
    html_dom.tag = .html;

    var body_dom = dom.Node.init(allocator, .element);
    body_dom.tag = .body;
    body_dom.parent = &html_dom;

    var flex_div_dom = dom.Node.init(allocator, .element);
    flex_div_dom.tag = .div;
    flex_div_dom.parent = &body_dom;

    var inner_div_dom = dom.Node.init(allocator, .element);
    inner_div_dom.tag = .div;
    inner_div_dom.parent = &flex_div_dom;

    var inner_style = properties.ComputedStyle{};
    inner_style.display = .block;
    inner_style.height = .{ .value = 200, .unit = .px };

    var inner_sn = resolver.StyledNode{
        .node = &inner_div_dom,
        .style = inner_style,
        .children = &.{},
    };

    var flex_style = properties.ComputedStyle{};
    flex_style.display = .flex;
    flex_style.flex_direction = .column;
    flex_style.height = .{ .value = 800, .unit = .px };

    const flex_children = try allocator.alloc(*resolver.StyledNode, 1);
    flex_children[0] = &inner_sn;

    var flex_sn = resolver.StyledNode{
        .node = &flex_div_dom,
        .style = flex_style,
        .children = flex_children,
    };

    var body_style = properties.ComputedStyle{};
    body_style.display = .block;

    const body_children = try allocator.alloc(*resolver.StyledNode, 1);
    body_children[0] = &flex_sn;

    var body_sn = resolver.StyledNode{
        .node = &body_dom,
        .style = body_style,
        .children = body_children,
    };

    var html_style = properties.ComputedStyle{};
    html_style.display = .block;
    html_style.height = .{ .value = 800, .unit = .px };

    const html_children = try allocator.alloc(*resolver.StyledNode, 1);
    html_children[0] = &body_sn;

    var html_sn = resolver.StyledNode{
        .node = &html_dom,
        .style = html_style,
        .children = html_children,
    };

    const root_box = try layout.buildLayoutTree(allocator, &html_sn);
    layout.layoutTree(root_box, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    try std.testing.expectEqual(@as(f32, 1200), root_box.dimensions.content.width);

    const body_box = root_box.children.items[0];
    const flex_box = body_box.children.items[0];

    try std.testing.expectEqual(@as(f32, 800), flex_box.dimensions.content.height);
    try std.testing.expect(body_box.dimensions.content.height > 0);
    try std.testing.expectEqual(@as(f32, 800), body_box.dimensions.content.height);
}

test "RC-3: block parent with margin accumulates flex child height" {
    // More realistic: body has margin: 8px (like UA stylesheet), no padding/border.
    // parent_can_collapse_top = true for body (not root, no padding/border top).
    // The first child (flex div) margin collapsing should NOT prevent height accumulation.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var html_dom = dom.Node.init(allocator, .element);
    html_dom.tag = .html;

    var body_dom = dom.Node.init(allocator, .element);
    body_dom.tag = .body;
    body_dom.parent = &html_dom;

    var flex_div_dom = dom.Node.init(allocator, .element);
    flex_div_dom.tag = .div;
    flex_div_dom.parent = &body_dom;

    var inner_div_dom = dom.Node.init(allocator, .element);
    inner_div_dom.tag = .div;
    inner_div_dom.parent = &flex_div_dom;

    var inner_style = properties.ComputedStyle{};
    inner_style.display = .block;
    inner_style.height = .{ .value = 200, .unit = .px };

    var inner_sn = resolver.StyledNode{
        .node = &inner_div_dom,
        .style = inner_style,
        .children = &.{},
    };

    var flex_style = properties.ComputedStyle{};
    flex_style.display = .flex;
    flex_style.flex_direction = .column;
    flex_style.height = .{ .value = 800, .unit = .px };

    const flex_children = try allocator.alloc(*resolver.StyledNode, 1);
    flex_children[0] = &inner_sn;

    var flex_sn = resolver.StyledNode{
        .node = &flex_div_dom,
        .style = flex_style,
        .children = flex_children,
    };

    // Body with UA-like margin: 8px
    var body_style = properties.ComputedStyle{};
    body_style.display = .block;
    body_style.margin_top = .{ .value = 8, .unit = .px };
    body_style.margin_bottom = .{ .value = 8, .unit = .px };
    body_style.margin_left = .{ .value = 8, .unit = .px };
    body_style.margin_right = .{ .value = 8, .unit = .px };
    // No padding, no border -> parent_can_collapse_top = true

    const body_children = try allocator.alloc(*resolver.StyledNode, 1);
    body_children[0] = &flex_sn;

    var body_sn = resolver.StyledNode{
        .node = &body_dom,
        .style = body_style,
        .children = body_children,
    };

    var html_style = properties.ComputedStyle{};
    html_style.display = .block;
    html_style.height = .{ .value = 800, .unit = .px };

    const html_children = try allocator.alloc(*resolver.StyledNode, 1);
    html_children[0] = &body_sn;

    var html_sn = resolver.StyledNode{
        .node = &html_dom,
        .style = html_style,
        .children = html_children,
    };

    const root_box = try layout.buildLayoutTree(allocator, &html_sn);
    layout.layoutTree(root_box, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    const body_box = root_box.children.items[0];
    const flex_box = body_box.children.items[0];

    // Flex div should have height 800
    try std.testing.expectEqual(@as(f32, 800), flex_box.dimensions.content.height);

    // CRITICAL: body should have height 800 (accumulated from flex child), NOT 0
    try std.testing.expect(body_box.dimensions.content.height > 0);
    try std.testing.expectEqual(@as(f32, 800), body_box.dimensions.content.height);

    // Body width should be 1200 - 16 (margins)
    try std.testing.expectEqual(@as(f32, 1184), body_box.dimensions.content.width);
}

test "RC-3: Google-like structure with empty div before flex child" {
    // Reproduces Google.com structure: body has an empty div[0] (ZnpjSd)
    // before the main flex container div[1] (L3eUgb).
    // CRITICAL: Both html and body have height:100% and margin:0; padding:0.
    // body's height:100% resolves against html's height (which is also 100% = viewport).
    // The bug: body's percentage height resolves against html's content.height which is
    // still 0 during html's layoutChildren, causing body to get height 0.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var html_dom = dom.Node.init(allocator, .element);
    html_dom.tag = .html;

    var body_dom = dom.Node.init(allocator, .element);
    body_dom.tag = .body;
    body_dom.parent = &html_dom;

    var empty_div_dom = dom.Node.init(allocator, .element);
    empty_div_dom.tag = .div;
    empty_div_dom.parent = &body_dom;

    var flex_div_dom = dom.Node.init(allocator, .element);
    flex_div_dom.tag = .div;
    flex_div_dom.parent = &body_dom;

    var inner_div_dom = dom.Node.init(allocator, .element);
    inner_div_dom.tag = .div;
    inner_div_dom.parent = &flex_div_dom;

    // Inner content
    var inner_style = properties.ComputedStyle{};
    inner_style.display = .block;
    inner_style.height = .{ .value = 200, .unit = .px };

    var inner_sn = resolver.StyledNode{
        .node = &inner_div_dom,
        .style = inner_style,
        .children = &.{},
    };

    // Empty div (like Google's #ZnpjSd)
    var empty_style = properties.ComputedStyle{};
    empty_style.display = .block;

    var empty_sn = resolver.StyledNode{
        .node = &empty_div_dom,
        .style = empty_style,
        .children = &.{},
    };

    // Flex column container (like Google's .L3eUgb) with height: 100%
    var flex_style = properties.ComputedStyle{};
    flex_style.display = .flex;
    flex_style.flex_direction = .column;
    flex_style.height = .{ .value = 100, .unit = .percent }; // height: 100%

    const flex_children = try allocator.alloc(*resolver.StyledNode, 1);
    flex_children[0] = &inner_sn;

    var flex_sn = resolver.StyledNode{
        .node = &flex_div_dom,
        .style = flex_style,
        .children = flex_children,
    };

    // Body: height:100%, margin:0, padding:0 (Google's CSS: body,html{height:100%;margin:0;padding:0})
    var body_style = properties.ComputedStyle{};
    body_style.display = .block;
    body_style.height = .{ .value = 100, .unit = .percent }; // height: 100%

    const body_children = try allocator.alloc(*resolver.StyledNode, 2);
    body_children[0] = &empty_sn;
    body_children[1] = &flex_sn;

    var body_sn = resolver.StyledNode{
        .node = &body_dom,
        .style = body_style,
        .children = body_children,
    };

    // HTML: height:100% (resolves to viewport=800), margin:0, padding:0
    var html_style = properties.ComputedStyle{};
    html_style.display = .block;
    html_style.height = .{ .value = 100, .unit = .percent }; // height: 100%

    const html_children = try allocator.alloc(*resolver.StyledNode, 1);
    html_children[0] = &body_sn;

    var html_sn = resolver.StyledNode{
        .node = &html_dom,
        .style = html_style,
        .children = html_children,
    };

    const root_box = try layout.buildLayoutTree(allocator, &html_sn);
    layout.layoutTree(root_box, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    const body_box = root_box.children.items[0];
    try std.testing.expectEqual(@as(usize, 2), body_box.children.items.len);

    const flex_box = body_box.children.items[1];

    // HTML should have height 800 (100% of viewport)
    try std.testing.expectEqual(@as(f32, 800), root_box.dimensions.content.height);

    // Body should have height 800 (100% of html = 800)
    // BUG: Currently body gets 0 because html's content.height is 0 when body's
    // calculateHeight resolves the percentage.
    try std.testing.expectEqual(@as(f32, 800), body_box.dimensions.content.height);

    // Flex div height: 100% of body. If body is 800, flex should be 800.
    try std.testing.expectEqual(@as(f32, 800), flex_box.dimensions.content.height);
}

test "RC-3: document node as root — resolveDefiniteHeight returns viewport height" {
    // In the real pipeline (dump_dom), the styled tree root is a document node,
    // not an element. html's parent is the document LayoutBox. When html has
    // height:100%, resolveDefiniteHeight walks up to the document box whose
    // styled_node.style.height is null. Without the fix, it returns
    // content.height (0) instead of viewport_height.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Document DOM node (the root of the real DOM tree)
    var doc_dom = dom.Node.init(allocator, .document);

    var html_dom = dom.Node.init(allocator, .element);
    html_dom.tag = .html;
    html_dom.parent = &doc_dom;

    var body_dom = dom.Node.init(allocator, .element);
    body_dom.tag = .body;
    body_dom.parent = &html_dom;

    var div_dom = dom.Node.init(allocator, .element);
    div_dom.tag = .div;
    div_dom.parent = &body_dom;

    // Inner content div (gives the flex container something to size)
    var inner_style = properties.ComputedStyle{};
    inner_style.display = .block;
    inner_style.height = .{ .value = 200, .unit = .px };

    var inner_sn = resolver.StyledNode{
        .node = &div_dom,
        .style = inner_style,
        .children = &.{},
    };

    // Body: height:100%
    var body_style = properties.ComputedStyle{};
    body_style.display = .flex;
    body_style.flex_direction = .column;
    body_style.height = .{ .value = 100, .unit = .percent };

    const body_children = try allocator.alloc(*resolver.StyledNode, 1);
    body_children[0] = &inner_sn;

    var body_sn = resolver.StyledNode{
        .node = &body_dom,
        .style = body_style,
        .children = body_children,
    };

    // HTML: height:100%
    var html_style = properties.ComputedStyle{};
    html_style.display = .block;
    html_style.height = .{ .value = 100, .unit = .percent };

    const html_children = try allocator.alloc(*resolver.StyledNode, 1);
    html_children[0] = &body_sn;

    var html_sn = resolver.StyledNode{
        .node = &html_dom,
        .style = html_style,
        .children = html_children,
    };

    // Document: no explicit height (like the real pipeline)
    var doc_style = properties.ComputedStyle{};
    doc_style.display = .block;

    const doc_children = try allocator.alloc(*resolver.StyledNode, 1);
    doc_children[0] = &html_sn;

    var doc_sn = resolver.StyledNode{
        .node = &doc_dom,
        .style = doc_style,
        .children = doc_children,
    };

    // Build layout tree from document (as real pipeline does)
    const root_box = try layout.buildLayoutTree(allocator, &doc_sn);
    layout.layoutTree(root_box, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    // root_box is the document box; its first child is html
    const html_box = root_box.children.items[0];
    const body_box = html_box.children.items[0];

    // HTML height: 100% of document → should be 800 (viewport)
    try std.testing.expectEqual(@as(f32, 800), html_box.dimensions.content.height);

    // Body height: 100% of html → should be 800
    try std.testing.expectEqual(@as(f32, 800), body_box.dimensions.content.height);
}

test "RC-6b: inline-block element shrinks to fit content" {
    // CSS 2.1 §10.3.9: inline-block with width:auto should use shrink-to-fit width,
    // NOT fill the containing block like a normal block-level element.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Container: block, 1000px wide
    var container_dom = dom.Node.init(allocator, .element);
    container_dom.tag = .div;
    var container_style = properties.ComputedStyle{};
    container_style.display = .block;
    container_style.width = .{ .value = 1000, .unit = .px };

    // Inline-block child: NO explicit width — should shrink to fit content
    var ib_dom = dom.Node.init(allocator, .element);
    ib_dom.tag = .a;
    var ib_style = properties.ComputedStyle{};
    ib_style.display = .inline_block;
    // No width set — auto

    // Grandchild inside inline-block: block, explicit width 200px
    var gc_dom = dom.Node.init(allocator, .element);
    gc_dom.tag = .div;
    var gc_style = properties.ComputedStyle{};
    gc_style.display = .block;
    gc_style.width = .{ .value = 200, .unit = .px };
    gc_style.height = .{ .value = 50, .unit = .px };

    var gc_sn = resolver.StyledNode{
        .node = &gc_dom,
        .style = gc_style,
        .children = &.{},
    };

    const ib_children = try allocator.alloc(*resolver.StyledNode, 1);
    ib_children[0] = &gc_sn;

    var ib_sn = resolver.StyledNode{
        .node = &ib_dom,
        .style = ib_style,
        .children = ib_children,
    };

    const container_children = try allocator.alloc(*resolver.StyledNode, 1);
    container_children[0] = &ib_sn;

    var container_sn = resolver.StyledNode{
        .node = &container_dom,
        .style = container_style,
        .children = container_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_sn);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    // The inline-block is inside an anonymous block (wrapped by buildLayoutTree).
    // root = container (blockNode)
    //   -> anonymous block
    //     -> inline-block (inlineBlockNode)
    //       -> grandchild (blockNode, 200px)
    const anon_block = root.children.items[0];
    try std.testing.expectEqual(layout.BoxType.anonymousBlock, anon_block.box_type);

    const ib_box = anon_block.children.items[0];
    try std.testing.expectEqual(layout.BoxType.inlineBlockNode, ib_box.box_type);

    // The inline-block should shrink to fit its content (200px), NOT fill the container (1000px).
    try std.testing.expectEqual(@as(f32, 200), ib_box.dimensions.content.width);

    // The grandchild inside should be 200px
    const gc_box = ib_box.children.items[0];
    try std.testing.expectEqual(@as(f32, 200), gc_box.dimensions.content.width);
}

test "RC-6: flex item with no explicit width sizes to content" {
    // CSS Flexbox §9.2: When flex-basis is auto and width is auto,
    // the flex base size should be the item's max-content size.
    // A flex item with no explicit width/flex-basis should NOT get width 0.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Flex container: row direction, 1000px wide
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 1000, .unit = .px };

    // Child A: explicit width 300px (should still work correctly)
    var child_a_style = properties.ComputedStyle{};
    child_a_style.display = .block;
    child_a_style.width = .{ .value = 300, .unit = .px };

    var child_a_sn = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_a_style,
        .children = &.{},
    };

    // Child B: NO explicit width, NO flex-basis
    // Contains a grandchild with explicit width 150px.
    // Child B should size to its content, i.e., at least 150px, NOT 0.
    var grandchild_style = properties.ComputedStyle{};
    grandchild_style.display = .block;
    grandchild_style.width = .{ .value = 150, .unit = .px };
    grandchild_style.height = .{ .value = 50, .unit = .px };

    var grandchild_sn = resolver.StyledNode{
        .node = &dummy_node,
        .style = grandchild_style,
        .children = &.{},
    };

    var child_b_style = properties.ComputedStyle{};
    child_b_style.display = .block;
    // No width, no flex_basis — should auto-size to content

    const child_b_children = try allocator.alloc(*resolver.StyledNode, 1);
    child_b_children[0] = &grandchild_sn;

    var child_b_sn = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_b_style,
        .children = child_b_children,
    };

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = &.{},
    };
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child_a_sn;
    c_children[1] = &child_b_sn;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    const child_a_box = root.children.items[0];
    const child_b_box = root.children.items[1];

    // Child A with explicit width should be 300
    try std.testing.expectEqual(@as(f32, 300), child_a_box.dimensions.content.width);

    // Child B with no explicit width should shrink-to-fit its content.
    // Per CSS Flexbox §9.2, auto flex-basis + auto width → max-content size.
    // Child B contains a 150px-wide grandchild, so it should be 150px, NOT the
    // full container width (1000px).
    try std.testing.expectEqual(@as(f32, 150), child_b_box.dimensions.content.width);

    // The grandchild inside child B should have width 150
    try std.testing.expectEqual(@as(f32, 150), child_b_box.children.items[0].dimensions.content.width);
}

test "RC-6b: inline-block with text content shrinks to fit (anonymous block text_runs)" {
    // When an inline-block element (e.g., <a>) contains text, buildLayoutTree wraps
    // the text in an anonymous block. layoutInlineBlock produces text_runs on the
    // anonymous block, not on the <a> itself. The shrink-to-fit code must recurse
    // into anonymous blocks' text_runs to find the actual content extent.
    // Without the fix, the inline-block stays at container width or collapses to 0.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Container: block, 500px wide
    var container_dom = dom.Node.init(allocator, .element);
    container_dom.tag = .div;
    var container_style = properties.ComputedStyle{};
    container_style.display = .block;
    container_style.width = .{ .value = 500, .unit = .px };

    // Inline-block element: <a> with display:inline-block, no explicit width
    var ib_dom = dom.Node.init(allocator, .element);
    ib_dom.tag = .a;
    ib_dom.parent = &container_dom;
    var ib_style = properties.ComputedStyle{};
    ib_style.display = .inline_block;

    // Text node "Hello" inside the <a>
    var text_dom = dom.Node.init(allocator, .text);
    text_dom.data = "Hello";
    text_dom.parent = &ib_dom;
    var text_style = properties.ComputedStyle{};
    text_style.display = .inline_val;
    text_style.font_size = .{ .value = 16.0, .unit = .px };
    text_style.font_weight = 400;

    var text_sn = resolver.StyledNode{
        .node = &text_dom,
        .style = text_style,
        .children = &.{},
    };

    const ib_children = try allocator.alloc(*resolver.StyledNode, 1);
    ib_children[0] = &text_sn;

    var ib_sn = resolver.StyledNode{
        .node = &ib_dom,
        .style = ib_style,
        .children = ib_children,
    };

    const container_children = try allocator.alloc(*resolver.StyledNode, 1);
    container_children[0] = &ib_sn;

    var container_sn = resolver.StyledNode{
        .node = &container_dom,
        .style = container_style,
        .children = container_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_sn);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    // Structure after buildLayoutTree:
    // root (container, blockNode)
    //   -> anonymous block (wraps inline content)
    //     -> inline-block <a> (inlineBlockNode)
    //       -> anonymous block (wraps text node inside <a>)
    //         -> text node "Hello" (inlineNode)
    //
    // The text_runs for "Hello" are on the inner anonymous block, NOT on the <a>.
    // The fix ensures shrink-to-fit recurses into anonymous blocks' text_runs.

    const outer_anon = root.children.items[0];
    try std.testing.expectEqual(layout.BoxType.anonymousBlock, outer_anon.box_type);

    const ib_box = outer_anon.children.items[0];
    try std.testing.expectEqual(layout.BoxType.inlineBlockNode, ib_box.box_type);

    // Measure expected text width: "Hello" at 16px, weight 400
    // Fallback measure: 5 chars * 8px = 40px
    const expected_text_width = layout.text_measure.measureTextWidth("Hello", 16.0, 400);

    // The inline-block should shrink to approximately the text width, NOT stay at 500px.
    // It must be > 0 (not collapsed) and close to expected_text_width.
    try std.testing.expect(ib_box.dimensions.content.width > 0);
    try std.testing.expect(ib_box.dimensions.content.width < 500);
    try std.testing.expect(@abs(ib_box.dimensions.content.width - expected_text_width) <= 2.0);
}

test "RC-7: flex container height with border-box subtracts padding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: display:flex, flex-direction:row, height:60px,
    // box-sizing:border-box, padding-top:6px, padding-bottom:6px
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 300, .unit = .px };
    container_style.height = .{ .value = 60, .unit = .px };
    container_style.box_sizing = .border_box;
    container_style.padding_top = .{ .value = 6, .unit = .px };
    container_style.padding_bottom = .{ .value = 6, .unit = .px };

    // One child with no explicit height
    var child_style = properties.ComputedStyle{};
    child_style.display = .block;

    var child_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_style,
        .children = &.{},
    };

    const c_children = try allocator.alloc(*resolver.StyledNode, 1);
    c_children[0] = &child_node;

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = c_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    // Content height should be 60 - 6 - 6 = 48 (border-box subtracts padding)
    try std.testing.expectEqual(@as(f32, 48), root.dimensions.content.height);

    // Total margin box height should be 60 (content 48 + padding 6+6)
    try std.testing.expectEqual(@as(f32, 60), root.dimensions.marginBox().height);
}

test "RC-8: flex container respects min-height" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: column flex, min_height 150px, no explicit height, no children with height
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .column;
    container_style.width = .{ .value = 300, .unit = .px };
    container_style.min_height = .{ .value = 150, .unit = .px };

    // One child with no explicit height (will be 0)
    var child_style = properties.ComputedStyle{};
    child_style.display = .block;

    var child_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_style,
        .children = &.{},
    };

    const c_children = try allocator.alloc(*resolver.StyledNode, 1);
    c_children[0] = &child_node;

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = c_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    // min-height: 150px should clamp height upward from 0
    try std.testing.expect(root.dimensions.content.height >= 150);

    // Now test max-height clamping: min_height 150, max_height 100 -> max wins, content.height = 100
    var container_style2 = properties.ComputedStyle{};
    container_style2.display = .flex;
    container_style2.flex_direction = .column;
    container_style2.width = .{ .value = 300, .unit = .px };
    container_style2.min_height = .{ .value = 150, .unit = .px };
    container_style2.max_height = .{ .value = 100, .unit = .px };

    var child_style2 = properties.ComputedStyle{};
    child_style2.display = .block;

    var child_node2 = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_style2,
        .children = &.{},
    };

    const c_children2 = try allocator.alloc(*resolver.StyledNode, 1);
    c_children2[0] = &child_node2;

    var container_node2 = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style2,
        .children = c_children2,
    };

    const root2 = try layout.buildLayoutTree(allocator, &container_node2);
    layout.layoutTree(root2, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    // max-height: 100px should clamp downward after min-height pushed it to 150
    try std.testing.expectEqual(@as(f32, 100), root2.dimensions.content.height);
}

test "RC-9: inline-block children in flex container are separate flex items" {
    // Flex container with two inline-block children should NOT wrap them in an anonymous block.
    // Each inline-block child is a separate flex item per CSS Flexbox spec.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: display:flex, flex-direction:row, width:400
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 400, .unit = .px };

    // Child 1: inline-block, width:50
    var child1_style = properties.ComputedStyle{};
    child1_style.display = .inline_block;
    child1_style.width = .{ .value = 50, .unit = .px };
    child1_style.height = .{ .value = 30, .unit = .px };

    var child1_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child1_style,
        .children = &.{},
    };

    // Child 2: inline-block, width:50
    var child2_style = properties.ComputedStyle{};
    child2_style.display = .inline_block;
    child2_style.width = .{ .value = 50, .unit = .px };
    child2_style.height = .{ .value = 30, .unit = .px };

    var child2_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child2_style,
        .children = &.{},
    };

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
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 400, .viewport_height = 300 });

    // Both children should be direct flex items (not wrapped in a single anonymous block)
    // If wrapped, there would be 1 child (the anonymous block) instead of 2.
    try std.testing.expectEqual(@as(usize, 2), root.children.items.len);

    // First child x = container content x (0)
    try std.testing.expectEqual(@as(f32, 0), root.children.items[0].dimensions.content.x);

    // Second child x = first child margin box width (50)
    try std.testing.expectEqual(@as(f32, 50), root.children.items[1].dimensions.content.x);

    // They should have DIFFERENT x positions
    try std.testing.expect(root.children.items[0].dimensions.content.x != root.children.items[1].dimensions.content.x);
}

test "RC-9: flex container with align-items center positions inline-block items correctly" {
    // Flex container with align-items:center and an inline-block child.
    // The child should be vertically centered, not have a negative y.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: display:flex, flex-direction:row, width:400, height:60,
    // box-sizing:border-box, padding:6, align-items:center
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 400, .unit = .px };
    container_style.height = .{ .value = 60, .unit = .px };
    container_style.box_sizing = .border_box;
    container_style.padding_top = .{ .value = 6, .unit = .px };
    container_style.padding_bottom = .{ .value = 6, .unit = .px };
    container_style.padding_left = .{ .value = 6, .unit = .px };
    container_style.padding_right = .{ .value = 6, .unit = .px };
    container_style.align_items = .center;

    // One inline-block child, height:26
    var child_style = properties.ComputedStyle{};
    child_style.display = .inline_block;
    child_style.height = .{ .value = 26, .unit = .px };
    child_style.width = .{ .value = 100, .unit = .px };

    var child_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_style,
        .children = &.{},
    };

    const c_children = try allocator.alloc(*resolver.StyledNode, 1);
    c_children[0] = &child_node;

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = c_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    // Content height = 60 - 6 - 6 = 48 (border-box)
    try std.testing.expectEqual(@as(f32, 48), root.dimensions.content.height);

    // The inline-block child should be a direct flex item (not wrapped)
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);

    const child_box = root.children.items[0];

    // Child y should be container.content.y + (48 - 26) / 2 = content.y + 11
    const expected_y = root.dimensions.content.y + (48 - 26) / 2;
    try std.testing.expectEqual(expected_y, child_box.dimensions.content.y);

    // Child y should be POSITIVE (not negative)
    try std.testing.expect(child_box.dimensions.content.y > 0);
}

test "RC-10: SVG elements get inline-block display from UA stylesheet" {
    // Parse the UA stylesheet and verify that the 'svg' tag gets display:inline-block.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stylesheet = try user_agent.getStylesheet(allocator);

    // Search for a rule with selector matching "svg"
    var found_svg = false;
    var svg_display: ?properties.Display = null;
    for (stylesheet.rules) |rule| {
        for (rule.selectors) |sel| {
            if (sel.components.len == 1 and sel.components[0].part.tag != null and
                std.mem.eql(u8, sel.components[0].part.tag.?, "svg"))
            {
                found_svg = true;
                // Apply declarations to a fresh style to get the display value
                var style = properties.ComputedStyle{};
                for (rule.declarations) |decl| {
                    try style.applyProperty(decl.property, decl.value, allocator);
                }
                svg_display = style.display;
                break;
            }
        }
        if (found_svg) break;
    }

    try std.testing.expect(found_svg);
    try std.testing.expectEqual(properties.Display.inline_block, svg_display.?);
}

test "RC-11: percentage max-height treated as none when CB height is indefinite" {
    // Reproduces the Google logo SVG bug: an SVG with intrinsic height=92 inside
    // a chain of height:100% containers where the outermost has no explicit height.
    // max-height:100% should be treated as none (CSS 2.1 §10.7) because the
    // containing block's height is indefinite.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Outer flex column container (like #LS8OJ) — no explicit height
    var outer_style = properties.ComputedStyle{};
    outer_style.display = .flex;
    outer_style.flex_direction = .column;
    outer_style.width = .{ .value = 400, .unit = .px };
    // No height set — height is auto/indefinite

    // Middle child (like .k1zIA) — height: 100%
    var middle_style = properties.ComputedStyle{};
    middle_style.display = .block;
    middle_style.height = .{ .value = 100, .unit = .percent };

    // Inner element (the SVG) — max-height: 100%, with intrinsic dimensions
    var inner_style = properties.ComputedStyle{};
    inner_style.display = .inline_block;
    inner_style.max_height = .{ .value = 100, .unit = .percent };
    inner_style.max_width = .{ .value = 100, .unit = .percent };
    inner_style.width = .{ .value = 0, .unit = .auto };

    var inner_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = inner_style,
        .children = &.{},
    };

    const middle_children = try allocator.alloc(*resolver.StyledNode, 1);
    middle_children[0] = &inner_node;

    var middle_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = middle_style,
        .children = middle_children,
    };

    const outer_children = try allocator.alloc(*resolver.StyledNode, 1);
    outer_children[0] = &middle_node;

    var outer_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = outer_style,
        .children = outer_children,
    };

    const root = try layout.buildLayoutTree(allocator, &outer_node);

    // Set intrinsic dimensions on the inner layout box (the SVG element).
    // buildLayoutTree only sets these for actual SVG DOM nodes; we set them manually.
    // Structure: root (flex) -> middle_box (block) -> anon_block (anonymous) -> inner_box (inlineBlock)
    const middle_box = root.children.items[0];
    const anon_box = middle_box.children.items[0];
    const inner_box = anon_box.children.items[0];
    inner_box.intrinsic_width = 272;
    inner_box.intrinsic_height = 92;

    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    // The inner element should have height = 92 (from intrinsic height).
    // Bug: max-height:100% resolves to 0 because CB height is indefinite,
    // clamping intrinsic height to 0.
    const inner_height = inner_box.dimensions.content.height;
    try std.testing.expect(inner_height > 0);
    try std.testing.expectEqual(@as(f32, 92), inner_height);
}

test "RC-12: parseLength handles calc expressions" {
    // calc(100% - 560px) → unit=.calc, value=100, calc_offset=-560
    const l1 = values.parseLength("calc(100% - 560px)") orelse unreachable;
    try std.testing.expectEqual(values.Unit.calc, l1.unit);
    try std.testing.expectEqual(@as(f32, 100), l1.value);
    try std.testing.expectEqual(@as(f32, -560), l1.calc_offset);

    // calc(100% + 20px) → unit=.calc, value=100, calc_offset=20
    const l2 = values.parseLength("calc(100% + 20px)") orelse unreachable;
    try std.testing.expectEqual(values.Unit.calc, l2.unit);
    try std.testing.expectEqual(@as(f32, 100), l2.value);
    try std.testing.expectEqual(@as(f32, 20), l2.calc_offset);

    // calc(100px - 50px) → unit=.px, value=50
    const l3 = values.parseLength("calc(100px - 50px)") orelse unreachable;
    try std.testing.expectEqual(values.Unit.px, l3.unit);
    try std.testing.expectEqual(@as(f32, 50), l3.value);

    // calc(100px + 50px) → unit=.px, value=150
    const l4 = values.parseLength("calc(100px + 50px)") orelse unreachable;
    try std.testing.expectEqual(values.Unit.px, l4.unit);
    try std.testing.expectEqual(@as(f32, 150), l4.value);

    // calc(50% + 25%) → unit=.percent, value=75
    const l5 = values.parseLength("calc(50% + 25%)") orelse unreachable;
    try std.testing.expectEqual(values.Unit.percent, l5.unit);
    try std.testing.expectEqual(@as(f32, 75), l5.value);
}

test "RC-12: basic calc() support for height" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: 800px tall (simulating viewport/CB), display: flex, column
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .column;
    container_style.width = .{ .value = 1024, .unit = .px };
    container_style.height = .{ .value = 800, .unit = .px };

    // Child: height: calc(100% - 560px) — should resolve to 240px
    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.height = values.parseLength("calc(100% - 560px)");

    var child_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_style,
        .children = &.{},
    };

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = &.{},
    };

    // Wire up StyledNode children
    const c_children = try allocator.alloc(*resolver.StyledNode, 1);
    c_children[0] = &child_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1024, .viewport_height = 800 });

    // The child's height should be calc(100% - 560px) = (100/100)*800 - 560 = 240
    const child_box = root.children.items[0];
    try std.testing.expectApproxEqAbs(@as(f32, 240), child_box.dimensions.content.height, 1.0);
}

test "RC-13: inline-block flex items measure text width correctly with padding" {
    // Reproduces the bug where <a> elements (.MV3Tnb) in Google's nav bar have
    // borderBox width of only 10px instead of ~56px. The <a> elements are
    // inline-block flex items with padding:5px 8px, margin:0 5px, containing
    // text like "About" (5 chars).
    //
    // Expected: content.width = text_width("About") = 40px (5 chars * 8px fallback)
    //           borderBox.width = 40 + 8 + 8 = 56px (content + padding)
    //           marginBox.width = 56 + 5 + 5 = 66px (border-box + margins)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // DOM nodes with parent chain
    var container_dom = dom.Node.init(allocator, .element);
    container_dom.tag = .div;

    var a_dom = dom.Node.init(allocator, .element);
    a_dom.tag = .a;
    a_dom.parent = &container_dom;

    var text_dom = dom.Node.init(allocator, .text);
    text_dom.data = "About";
    text_dom.parent = &a_dom;

    // Container: display:flex, flex-direction:row, width:1000, align-items:center
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 1000, .unit = .px };
    container_style.align_items = .center;

    // <a>: display:inline-block, padding:5px 8px, margin:0 5px
    var a_style = properties.ComputedStyle{};
    a_style.display = .inline_block;
    a_style.padding_top = .{ .value = 5, .unit = .px };
    a_style.padding_right = .{ .value = 8, .unit = .px };
    a_style.padding_bottom = .{ .value = 5, .unit = .px };
    a_style.padding_left = .{ .value = 8, .unit = .px };
    a_style.margin_top = .{ .value = 0, .unit = .px };
    a_style.margin_right = .{ .value = 5, .unit = .px };
    a_style.margin_bottom = .{ .value = 0, .unit = .px };
    a_style.margin_left = .{ .value = 5, .unit = .px };

    // Text node: inline
    var text_style = properties.ComputedStyle{};
    text_style.display = .inline_val;
    text_style.font_size = .{ .value = 16.0, .unit = .px };
    text_style.font_weight = 400;

    var text_sn = resolver.StyledNode{
        .node = &text_dom,
        .style = text_style,
        .children = &.{},
    };

    const a_children = try allocator.alloc(*resolver.StyledNode, 1);
    a_children[0] = &text_sn;

    var a_sn = resolver.StyledNode{
        .node = &a_dom,
        .style = a_style,
        .children = a_children,
    };

    const container_children = try allocator.alloc(*resolver.StyledNode, 1);
    container_children[0] = &a_sn;

    var container_sn = resolver.StyledNode{
        .node = &container_dom,
        .style = container_style,
        .children = container_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_sn);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    // The <a> should be a direct flex item (inline-block in flex = block-level)
    // Structure: root (flex) -> <a> (inlineBlockNode) -> anon block -> text "About"
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);

    const a_box = root.children.items[0];
    try std.testing.expectEqual(layout.BoxType.inlineBlockNode, a_box.box_type);

    // Padding should be applied
    try std.testing.expectEqual(@as(f32, 8), a_box.dimensions.padding.left);
    try std.testing.expectEqual(@as(f32, 8), a_box.dimensions.padding.right);

    // Margins should be applied
    try std.testing.expectEqual(@as(f32, 5), a_box.dimensions.margin.left);
    try std.testing.expectEqual(@as(f32, 5), a_box.dimensions.margin.right);

    // Text width: "About" = 5 chars * 8px = 40px (fallback)
    const expected_text_width = layout.text_measure.measureTextWidth("About", 16.0, 400);

    // Content width should be the text width (~40px), NOT 0 or container-width
    try std.testing.expect(a_box.dimensions.content.width > 0);
    try std.testing.expectApproxEqAbs(expected_text_width, a_box.dimensions.content.width, 2.0);

    // borderBox width should include padding: text_width + 8 + 8 = ~56
    const border_box = a_box.dimensions.borderBox();
    const expected_border_box_width = expected_text_width + 8 + 8;
    try std.testing.expectApproxEqAbs(expected_border_box_width, border_box.width, 2.0);

    // marginBox width should include margins: border_box + 5 + 5 = ~66
    const margin_box = a_box.dimensions.marginBox();
    const expected_margin_box_width = expected_border_box_width + 5 + 5;
    try std.testing.expectApproxEqAbs(expected_margin_box_width, margin_box.width, 2.0);
}

test "RC-13b: inline-block flex items with flex-grow sibling measure text width correctly" {
    // Reproduces the Google nav bar bug: <a> elements (display:inline-block) alongside
    // a flex-grow:1 sibling in a flex row. The grow pass sets lock_content_width=true
    // on ALL children (even those with flex_grow=0 that got extra=0), which prevents
    // Pass 2b shrink-to-fit from measuring the text content. Result: content.width=0,
    // borderBox.width = padding only (10px instead of ~56px).
    //
    // Structure: .Ne6nSd (flex row, padding:6) contains:
    //   1. <a> "About" (inline-block, padding:5px 8px, margin:0 5px)
    //   2. <a> "Store" (inline-block, padding:5px 8px, margin:0 5px)
    //   3. .LX3sZb (flex-grow:1)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // DOM nodes
    var container_dom = dom.Node.init(allocator, .element);
    container_dom.tag = .div;

    var a1_dom = dom.Node.init(allocator, .element);
    a1_dom.tag = .a;
    a1_dom.parent = &container_dom;

    var text1_dom = dom.Node.init(allocator, .text);
    text1_dom.data = "About";
    text1_dom.parent = &a1_dom;

    var a2_dom = dom.Node.init(allocator, .element);
    a2_dom.tag = .a;
    a2_dom.parent = &container_dom;

    var text2_dom = dom.Node.init(allocator, .text);
    text2_dom.data = "Store";
    text2_dom.parent = &a2_dom;

    var grow_dom = dom.Node.init(allocator, .element);
    grow_dom.tag = .div;
    grow_dom.parent = &container_dom;

    // Container: display:flex, flex-direction:row, width:1000, padding:6, align-items:center
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 1000, .unit = .px };
    container_style.padding_top = .{ .value = 6, .unit = .px };
    container_style.padding_bottom = .{ .value = 6, .unit = .px };
    container_style.padding_left = .{ .value = 6, .unit = .px };
    container_style.padding_right = .{ .value = 6, .unit = .px };
    container_style.align_items = .center;

    // <a> style: display:inline-block, padding:5px 8px, margin:0 5px
    var a_style = properties.ComputedStyle{};
    a_style.display = .inline_block;
    a_style.padding_top = .{ .value = 5, .unit = .px };
    a_style.padding_right = .{ .value = 8, .unit = .px };
    a_style.padding_bottom = .{ .value = 5, .unit = .px };
    a_style.padding_left = .{ .value = 8, .unit = .px };
    a_style.margin_top = .{ .value = 0, .unit = .px };
    a_style.margin_right = .{ .value = 5, .unit = .px };
    a_style.margin_bottom = .{ .value = 0, .unit = .px };
    a_style.margin_left = .{ .value = 5, .unit = .px };

    // Text node style
    var text_style = properties.ComputedStyle{};
    text_style.display = .inline_val;
    text_style.font_size = .{ .value = 16.0, .unit = .px };
    text_style.font_weight = 400;

    // flex-grow:1 child style
    var grow_style = properties.ComputedStyle{};
    grow_style.display = .block;
    grow_style.flex_grow = 1;

    // Build styled node tree
    var text1_sn = resolver.StyledNode{
        .node = &text1_dom,
        .style = text_style,
        .children = &.{},
    };

    const a1_children = try allocator.alloc(*resolver.StyledNode, 1);
    a1_children[0] = &text1_sn;

    var a1_sn = resolver.StyledNode{
        .node = &a1_dom,
        .style = a_style,
        .children = a1_children,
    };

    var text2_sn = resolver.StyledNode{
        .node = &text2_dom,
        .style = text_style,
        .children = &.{},
    };

    const a2_children = try allocator.alloc(*resolver.StyledNode, 1);
    a2_children[0] = &text2_sn;

    var a2_sn = resolver.StyledNode{
        .node = &a2_dom,
        .style = a_style,
        .children = a2_children,
    };

    var grow_sn = resolver.StyledNode{
        .node = &grow_dom,
        .style = grow_style,
        .children = &.{},
    };

    const container_children = try allocator.alloc(*resolver.StyledNode, 3);
    container_children[0] = &a1_sn;
    container_children[1] = &a2_sn;
    container_children[2] = &grow_sn;

    var container_sn = resolver.StyledNode{
        .node = &container_dom,
        .style = container_style,
        .children = container_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_sn);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    // Should have 3 direct flex items (inline-blocks are not wrapped in flex context)
    try std.testing.expectEqual(@as(usize, 3), root.children.items.len);

    const a1_box = root.children.items[0];
    const a2_box = root.children.items[1];

    try std.testing.expectEqual(layout.BoxType.inlineBlockNode, a1_box.box_type);
    try std.testing.expectEqual(layout.BoxType.inlineBlockNode, a2_box.box_type);

    // Text width: "About" / "Store" = 5 chars * 8px = 40px (fallback)
    const expected_text_width = layout.text_measure.measureTextWidth("About", 16.0, 400);

    // Content width should be text width (~40px), NOT 0
    try std.testing.expect(a1_box.dimensions.content.width > 0);
    try std.testing.expectApproxEqAbs(expected_text_width, a1_box.dimensions.content.width, 2.0);

    try std.testing.expect(a2_box.dimensions.content.width > 0);
    try std.testing.expectApproxEqAbs(expected_text_width, a2_box.dimensions.content.width, 2.0);

    // borderBox width should be text_width + padding: 40 + 8 + 8 = 56
    const a1_border = a1_box.dimensions.borderBox();
    const expected_border_w = expected_text_width + 8 + 8;
    try std.testing.expectApproxEqAbs(expected_border_w, a1_border.width, 2.0);

    // The flex-grow child should get all remaining space
    const grow_box = root.children.items[2];
    try std.testing.expect(grow_box.dimensions.content.width > 0);
}

test "Bug-1: flex item max-height applied even when height is flex-locked" {
    // Flex column container with height 300px.
    // Child has height:100% (resolves to 300) and max-height:92px.
    // The flex pass sets height=300 and locks it. calculateHeight is skipped.
    // max-height:92px must still be applied.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: flex column, height 300px
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .column;
    container_style.width = .{ .value = 500, .unit = .px };
    container_style.height = .{ .value = 300, .unit = .px };

    // Child: height:100% (resolves to 300 against container), max-height:92px
    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.height = .{ .value = 100, .unit = .percent };
    child_style.max_height = .{ .value = 92, .unit = .px };

    var child_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_style,
        .children = &.{},
    };

    const c_children = try allocator.alloc(*resolver.StyledNode, 1);
    c_children[0] = &child_node;

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = c_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 500, .viewport_height = 600 });

    // Child height should be clamped to 92 (max-height), NOT 300
    try std.testing.expectEqual(@as(f32, 92), root.children.items[0].dimensions.content.height);
}

test "Bug-2: flex column align-items center shrinks child to content width" {
    // Flex column container with width:1200, align-items:center.
    // Child has no explicit width, but contains a grandchild with explicit width:272.
    // Child should shrink to 272 (content width), NOT stay at 1200 (container width).
    // Child should be centered: x = container.x + (1200 - 272) / 2.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: flex column, width 1200, align-items:center
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .column;
    container_style.width = .{ .value = 1200, .unit = .px };
    container_style.align_items = .center;

    // Grandchild: block, explicit width 272, height 92
    var grandchild_style = properties.ComputedStyle{};
    grandchild_style.display = .block;
    grandchild_style.width = .{ .value = 272, .unit = .px };
    grandchild_style.height = .{ .value = 92, .unit = .px };

    var grandchild_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = grandchild_style,
        .children = &.{},
    };

    // Child: block, no explicit width (should shrink to content)
    var child_style = properties.ComputedStyle{};
    child_style.display = .block;

    const gc_children = try allocator.alloc(*resolver.StyledNode, 1);
    gc_children[0] = &grandchild_node;

    var child_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_style,
        .children = gc_children,
    };

    const c_children = try allocator.alloc(*resolver.StyledNode, 1);
    c_children[0] = &child_node;

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = c_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 600 });

    const child_box = root.children.items[0];

    // Child width should be 272 (content-based), NOT 1200 (container width)
    try std.testing.expectEqual(@as(f32, 272), child_box.dimensions.content.width);

    // Child should be centered: x = container.x + (1200 - 272) / 2 = 464
    const expected_x = root.dimensions.content.x + (1200 - 272) / 2;
    try std.testing.expectEqual(expected_x, child_box.dimensions.content.x);
}

test "Bug-3: margin-top auto in flex column pushes item to bottom" {
    // Flex column container with height:400px.
    // Child A: height:100px (normal).
    // Child B: height:100px, margin-top:auto.
    // margin-top:auto should absorb all free space, pushing B to the bottom.
    // Free space = 400 - 100 - 100 = 200. margin-top:auto absorbs 200.
    // B's y = container.y + 400 - 100 = container.y + 300.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: flex column, height 400px
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .column;
    container_style.width = .{ .value = 500, .unit = .px };
    container_style.height = .{ .value = 400, .unit = .px };

    // Child A: height 100px
    var child_a_style = properties.ComputedStyle{};
    child_a_style.display = .block;
    child_a_style.height = .{ .value = 100, .unit = .px };

    var child_a_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_a_style,
        .children = &.{},
    };

    // Child B: height 100px, margin-top:auto
    var child_b_style = properties.ComputedStyle{};
    child_b_style.display = .block;
    child_b_style.height = .{ .value = 100, .unit = .px };
    child_b_style.margin_top = .{ .value = 0, .unit = .auto };

    var child_b_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_b_style,
        .children = &.{},
    };

    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child_a_node;
    c_children[1] = &child_b_node;

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = c_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 500, .viewport_height = 600 });

    const child_a_box = root.children.items[0];
    const child_b_box = root.children.items[1];

    // Child A should be at the top
    try std.testing.expectEqual(root.dimensions.content.y, child_a_box.dimensions.content.y);

    // Child B should be pushed to the bottom: y = container.y + 400 - 100 = container.y + 300
    const expected_b_y = root.dimensions.content.y + 400 - 100;
    try std.testing.expectEqual(expected_b_y, child_b_box.dimensions.content.y);
}

test "RC-16: auto margin centering with max-width and no explicit width" {
    // Block element with margin:0 auto and max-width:584px but no explicit width.
    // Inside a 1200px container. Should be centered at x = (1200-584)/2 = 308.
    // This is the Google search bar pattern: .A8SBwf { margin: 0 auto; max-width: 584px; }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: 1200px wide block
    var container_style = properties.ComputedStyle{};
    container_style.display = .block;
    container_style.width = .{ .value = 1200, .unit = .px };

    // Child: no explicit width, max-width:584px, margin:0 auto
    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.max_width = .{ .value = 584, .unit = .px };
    child_style.margin_left = .{ .value = 0, .unit = .auto };
    child_style.margin_right = .{ .value = 0, .unit = .auto };

    var child_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_style,
        .children = &.{},
    };

    const c_children = try allocator.alloc(*resolver.StyledNode, 1);
    c_children[0] = &child_node;

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = c_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 1200, .viewport_height = 800 });

    const child_box = root.children.items[0];

    // Width should be clamped to 584 by max-width
    try std.testing.expectEqual(@as(f32, 584), child_box.dimensions.content.width);

    // Should be centered: margin_left = (1200 - 584) / 2 = 308
    try std.testing.expectEqual(@as(f32, 308), child_box.dimensions.margin.left);
    try std.testing.expectEqual(@as(f32, 308), child_box.dimensions.margin.right);

    // Content x = container.x + margin_left = 0 + 308 = 308
    try std.testing.expectEqual(@as(f32, 308), child_box.dimensions.content.x);
}

test "RC-17a: flex shorthand parsing for multi-value syntax" {
    // Test that flex: 0 0 auto is parsed correctly.
    // Parent is a row flex container with 600px width.
    // Child A: flex: 0 0 auto, width:100px → should stay at 100px (no grow, no shrink)
    // Child B: flex: 1 → should absorb remaining space (600 - 100 = 500px)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: row flex, 600px wide
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 600, .unit = .px };

    // Child A: flex: 0 0 auto, width:100px
    var child_a_style = properties.ComputedStyle{};
    child_a_style.display = .block;
    child_a_style.width = .{ .value = 100, .unit = .px };
    child_a_style.flex_grow = 0;
    child_a_style.flex_shrink = 0;
    child_a_style.flex_basis = .{ .value = 0, .unit = .auto };

    var child_a_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_a_style,
        .children = &.{},
    };

    // Child B: flex: 1
    var child_b_style = properties.ComputedStyle{};
    child_b_style.display = .block;
    child_b_style.flex_grow = 1;
    child_b_style.flex_shrink = 1;
    child_b_style.flex_basis = .{ .value = 0, .unit = .px };

    var child_b_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = child_b_style,
        .children = &.{},
    };

    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &child_a_node;
    c_children[1] = &child_b_node;

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = c_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 600, .viewport_height = 400 });

    const child_a_box = root.children.items[0];
    const child_b_box = root.children.items[1];

    // Child A should be 100px (explicit width, flex-basis:auto defers to width)
    try std.testing.expectEqual(@as(f32, 100), child_a_box.dimensions.content.width);

    // Child B should absorb remaining space: 600 - 100 = 500px
    try std.testing.expectEqual(@as(f32, 500), child_b_box.dimensions.content.width);
}

test "floats in separate flex items don't interfere" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Flex container: 400px wide, display: flex, row direction
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 400, .unit = .px };

    // Flex item 1: 200px wide block
    var item1_style = properties.ComputedStyle{};
    item1_style.display = .block;
    item1_style.width = .{ .value = 200, .unit = .px };

    // Float inside item 1: float right, 100x50
    var float1_style = properties.ComputedStyle{};
    float1_style.display = .block;
    float1_style.float = .right;
    float1_style.width = .{ .value = 100, .unit = .px };
    float1_style.height = .{ .value = 50, .unit = .px };

    var float1_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = float1_style,
        .children = &.{},
    };

    const item1_children = try allocator.alloc(*resolver.StyledNode, 1);
    item1_children[0] = &float1_node;

    var item1_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = item1_style,
        .children = item1_children,
    };

    // Flex item 2: 200px wide block
    var item2_style = properties.ComputedStyle{};
    item2_style.display = .block;
    item2_style.width = .{ .value = 200, .unit = .px };

    // Float inside item 2: float right, 100x50
    var float2_style = properties.ComputedStyle{};
    float2_style.display = .block;
    float2_style.float = .right;
    float2_style.width = .{ .value = 100, .unit = .px };
    float2_style.height = .{ .value = 50, .unit = .px };

    var float2_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = float2_style,
        .children = &.{},
    };

    const item2_children = try allocator.alloc(*resolver.StyledNode, 1);
    item2_children[0] = &float2_node;

    var item2_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = item2_style,
        .children = item2_children,
    };

    // Assemble flex container
    const c_children = try allocator.alloc(*resolver.StyledNode, 2);
    c_children[0] = &item1_node;
    c_children[1] = &item2_node;

    var container_node = resolver.StyledNode{
        .node = &dummy_node,
        .style = container_style,
        .children = c_children,
    };

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 400, .viewport_height = 300 });

    // Get the two flex items
    const item1_box = root.children.items[0];
    const item2_box = root.children.items[1];

    // Both flex items should be 200px wide
    try std.testing.expectEqual(@as(f32, 200), item1_box.dimensions.content.width);
    try std.testing.expectEqual(@as(f32, 200), item2_box.dimensions.content.width);

    // The float inside each item should start at y=0 within its item.
    // If BFC isolation is broken, the second float would be pushed down
    // by the first float from the sibling flex item.
    const float1_box = item1_box.children.items[0];
    const float2_box = item2_box.children.items[0];

    // Both floats should be at the same relative y position (top of their container).
    // The key assertion: float2's y position relative to its flex item should be 0,
    // NOT 50 (which would mean the first float leaked across BFC boundaries).
    const float1_rel_y = float1_box.dimensions.content.y - item1_box.dimensions.content.y;
    const float2_rel_y = float2_box.dimensions.content.y - item2_box.dimensions.content.y;

    try std.testing.expectEqual(@as(f32, 0), float1_rel_y);
    try std.testing.expectEqual(@as(f32, 0), float2_rel_y);
}

test "flex row justify-content space-evenly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: 300px wide, display: flex, justify-content: space-evenly
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 300, .unit = .px };
    container_style.justify_content = .space_evenly;

    // 3 children of 50px each => total content = 150px, available = 150px
    // space-evenly: gap = 150 / (3+1) = 37.5px
    // Positions: 37.5, 37.5+50+37.5=125.0, 125.0+50+37.5=212.5
    var child1_style = properties.ComputedStyle{};
    child1_style.display = .block;
    child1_style.width = .{ .value = 50, .unit = .px };
    child1_style.height = .{ .value = 20, .unit = .px };

    var child2_style = properties.ComputedStyle{};
    child2_style.display = .block;
    child2_style.width = .{ .value = 50, .unit = .px };
    child2_style.height = .{ .value = 20, .unit = .px };

    var child3_style = properties.ComputedStyle{};
    child3_style.display = .block;
    child3_style.width = .{ .value = 50, .unit = .px };
    child3_style.height = .{ .value = 20, .unit = .px };

    var child1_node = resolver.StyledNode{ .node = &dummy_node, .style = child1_style, .children = &.{} };
    var child2_node = resolver.StyledNode{ .node = &dummy_node, .style = child2_style, .children = &.{} };
    var child3_node = resolver.StyledNode{ .node = &dummy_node, .style = child3_style, .children = &.{} };

    var container_node = resolver.StyledNode{ .node = &dummy_node, .style = container_style, .children = &.{} };
    const c_children = try allocator.alloc(*resolver.StyledNode, 3);
    c_children[0] = &child1_node;
    c_children[1] = &child2_node;
    c_children[2] = &child3_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 300, .viewport_height = 600 });

    const c1 = root.children.items[0];
    const c2 = root.children.items[1];
    const c3 = root.children.items[2];

    // space-evenly: gap = 150 / 4 = 37.5
    try std.testing.expectApproxEqAbs(@as(f32, 37.5), c1.dimensions.content.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 125.0), c2.dimensions.content.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 212.5), c3.dimensions.content.x, 0.1);
}

test "flex row justify-content space-around" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dummy_node = dom.Node.init(allocator, .element);

    // Container: 300px wide, display: flex, justify-content: space-around
    var container_style = properties.ComputedStyle{};
    container_style.display = .flex;
    container_style.flex_direction = .row;
    container_style.width = .{ .value = 300, .unit = .px };
    container_style.justify_content = .space_around;

    // 3 children of 50px each => total content = 150px, available = 150px
    // space-around: gap = 150 / 3 = 50
    // Positions: 50/2=25.0, 25+50+50=125.0, 125+50+50=225.0
    var child1_style = properties.ComputedStyle{};
    child1_style.display = .block;
    child1_style.width = .{ .value = 50, .unit = .px };
    child1_style.height = .{ .value = 20, .unit = .px };

    var child2_style = properties.ComputedStyle{};
    child2_style.display = .block;
    child2_style.width = .{ .value = 50, .unit = .px };
    child2_style.height = .{ .value = 20, .unit = .px };

    var child3_style = properties.ComputedStyle{};
    child3_style.display = .block;
    child3_style.width = .{ .value = 50, .unit = .px };
    child3_style.height = .{ .value = 20, .unit = .px };

    var child1_node = resolver.StyledNode{ .node = &dummy_node, .style = child1_style, .children = &.{} };
    var child2_node = resolver.StyledNode{ .node = &dummy_node, .style = child2_style, .children = &.{} };
    var child3_node = resolver.StyledNode{ .node = &dummy_node, .style = child3_style, .children = &.{} };

    var container_node = resolver.StyledNode{ .node = &dummy_node, .style = container_style, .children = &.{} };
    const c_children = try allocator.alloc(*resolver.StyledNode, 3);
    c_children[0] = &child1_node;
    c_children[1] = &child2_node;
    c_children[2] = &child3_node;
    container_node.children = c_children;

    const root = try layout.buildLayoutTree(allocator, &container_node);
    layout.layoutTree(root, .{ .allocator = allocator, .viewport_width = 300, .viewport_height = 600 });

    const c1 = root.children.items[0];
    const c2 = root.children.items[1];
    const c3 = root.children.items[2];

    // space-around: gap = 150 / 3 = 50, half-gap = 25
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), c1.dimensions.content.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 125.0), c2.dimensions.content.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 225.0), c3.dimensions.content.x, 0.1);
}

test "RC-58: flex item suppresses parent-child margin collapsing (BFC)" {
    // A flex item (child of column flex container) establishes a BFC.
    // Its child <p> has UA margin-top:16px, margin-bottom:16px.
    // Without BFC suppression, the <p>'s bottom margin leaks into the
    // flex item's margin.bottom, reducing its flex-grow-allocated height.
    // With the fix, margins stay inside the flex item.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // DOM hierarchy: html > body > flex-container > flex-item > p
    var html_dom = dom.Node.init(allocator, .element);
    html_dom.tag = .html;

    var body_dom = dom.Node.init(allocator, .element);
    body_dom.tag = .body;
    body_dom.parent = &html_dom;

    var flex_div_dom = dom.Node.init(allocator, .element);
    flex_div_dom.tag = .div;
    flex_div_dom.parent = &body_dom;

    var item_div_dom = dom.Node.init(allocator, .element);
    item_div_dom.tag = .div;
    item_div_dom.parent = &flex_div_dom;

    var p_dom = dom.Node.init(allocator, .element);
    p_dom.tag = .p;
    p_dom.parent = &item_div_dom;

    // <p> with UA-like margins: margin-top: 16px, margin-bottom: 16px
    var p_style = properties.ComputedStyle{};
    p_style.display = .block;
    p_style.margin_top = .{ .value = 16, .unit = .px };
    p_style.margin_bottom = .{ .value = 16, .unit = .px };

    var p_sn = resolver.StyledNode{
        .node = &p_dom,
        .style = p_style,
        .children = &.{},
    };

    // Flex item: flex-grow: 1 (should fill the entire 200px container)
    var item_style = properties.ComputedStyle{};
    item_style.display = .block;
    item_style.flex_grow = 1;

    const item_children = try allocator.alloc(*resolver.StyledNode, 1);
    item_children[0] = &p_sn;

    var item_sn = resolver.StyledNode{
        .node = &item_div_dom,
        .style = item_style,
        .children = item_children,
    };

    // Flex container: column, height: 200px
    var flex_style = properties.ComputedStyle{};
    flex_style.display = .flex;
    flex_style.flex_direction = .column;
    flex_style.height = .{ .value = 200, .unit = .px };

    const flex_children = try allocator.alloc(*resolver.StyledNode, 1);
    flex_children[0] = &item_sn;

    var flex_sn = resolver.StyledNode{
        .node = &flex_div_dom,
        .style = flex_style,
        .children = flex_children,
    };

    // Body: no margin/padding/border for simplicity
    var body_style = properties.ComputedStyle{};
    body_style.display = .block;

    const body_children = try allocator.alloc(*resolver.StyledNode, 1);
    body_children[0] = &flex_sn;

    var body_sn = resolver.StyledNode{
        .node = &body_dom,
        .style = body_style,
        .children = body_children,
    };

    // HTML root
    var html_style = properties.ComputedStyle{};
    html_style.display = .block;

    const html_children = try allocator.alloc(*resolver.StyledNode, 1);
    html_children[0] = &body_sn;

    var html_sn = resolver.StyledNode{
        .node = &html_dom,
        .style = html_style,
        .children = html_children,
    };

    const root_box = try layout.buildLayoutTree(allocator, &html_sn);
    layout.layoutTree(root_box, .{ .allocator = allocator, .viewport_width = 800, .viewport_height = 600 });

    const body_box = root_box.children.items[0];
    const flex_box = body_box.children.items[0];
    const item_box = flex_box.children.items[0];

    // The flex item should fill the entire 200px (sole child with flex-grow:1)
    try std.testing.expectEqual(@as(f32, 200), item_box.dimensions.content.height);
    // The flex item's margin.bottom must be 0 — the <p>'s margin should NOT leak out
    try std.testing.expectEqual(@as(f32, 0), item_box.dimensions.margin.bottom);
}
