const std = @import("std");
const interaction = @import("../../src/render/interaction.zig");
const layout_box = @import("../../src/layout/box.zig");
const dom = @import("../../src/dom/mod.zig");
const resolver = @import("../../src/css/resolver.zig");
const properties = @import("../../src/css/properties.zig");
const events = @import("../../src/platform/events.zig");

test "Cursor on link" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    node.tag = .a;
    defer node.deinit(allocator);

    const style = properties.ComputedStyle{};
    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 200, .height = 50 };
    defer root.deinit(allocator);

    var handler = interaction.InteractionHandler{};
    const state = handler.handleMouseMove(&root, 10, 10, 0);
    try std.testing.expectEqual(interaction.InteractionHandler.CursorState.pointer, state);
}

test "Cursor on non-link" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    node.tag = .div;
    defer node.deinit(allocator);

    const style = properties.ComputedStyle{};
    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 200, .height = 50 };
    defer root.deinit(allocator);

    var handler = interaction.InteractionHandler{};
    const state = handler.handleMouseMove(&root, 10, 10, 0);
    try std.testing.expectEqual(interaction.InteractionHandler.CursorState.default_cursor, state);
}

test "Click on link with href" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    node.tag = .a;
    try node.attributes.append(allocator, .{ .name = "href", .value = "https://example.com" });
    defer node.deinit(allocator);

    const style = properties.ComputedStyle{};
    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 200, .height = 50 };
    defer root.deinit(allocator);

    var handler = interaction.InteractionHandler{};
    const result = handler.handleClick(&root, 10, 10, 0);
    try std.testing.expect(result.href != null);
    try std.testing.expectEqualStrings("https://example.com", result.href.?);
    try std.testing.expect(result.target_node != null);
}

test "Click on non-link" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    node.tag = .div;
    defer node.deinit(allocator);

    const style = properties.ComputedStyle{};
    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 200, .height = 50 };
    defer root.deinit(allocator);

    var handler = interaction.InteractionHandler{};
    const result = handler.handleClick(&root, 10, 10, 0);
    try std.testing.expect(result.href == null);
    try std.testing.expect(result.target_node != null);
}

test "Keyboard Cmd+Q" {
    const action = interaction.InteractionHandler.handleKeyDown(12, events.MOD_COMMAND);
    try std.testing.expectEqual(interaction.InteractionHandler.KeyAction.quit, action);
}

test "Keyboard Space" {
    const action = interaction.InteractionHandler.handleKeyDown(49, 0);
    try std.testing.expectEqual(interaction.InteractionHandler.KeyAction.scroll_down, action);
}

test "Keyboard Shift+Space" {
    const action = interaction.InteractionHandler.handleKeyDown(49, events.MOD_SHIFT);
    try std.testing.expectEqual(interaction.InteractionHandler.KeyAction.scroll_up, action);
}

test "Keyboard Home" {
    const action = interaction.InteractionHandler.handleKeyDown(115, 0);
    try std.testing.expectEqual(interaction.InteractionHandler.KeyAction.scroll_to_top, action);
}

test "Keyboard End" {
    const action = interaction.InteractionHandler.handleKeyDown(119, 0);
    try std.testing.expectEqual(interaction.InteractionHandler.KeyAction.scroll_to_bottom, action);
}

test "Unknown key" {
    const action = interaction.InteractionHandler.handleKeyDown(999, 0);
    try std.testing.expect(action == null);
}

test "Cursor on link ancestor-walking" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .a;
    defer parent_node.deinit(allocator);

    var child_node = dom.Node.init(allocator, .element);
    child_node.tag = .span;
    // Manual setup because we don't want to deal with full Document/limits
    child_node.parent = &parent_node;
    try parent_node.children.append(allocator, &child_node);

    const style = properties.ComputedStyle{};
    const sn = resolver.StyledNode{
        .node = &child_node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 200, .height = 50 };
    defer root.deinit(allocator);

    var handler = interaction.InteractionHandler{};
    const state = handler.handleMouseMove(&root, 10, 10, 0);
    try std.testing.expectEqual(interaction.InteractionHandler.CursorState.pointer, state);
}

test "Click on link with href ancestor-walking" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    parent_node.tag = .a;
    try parent_node.attributes.append(allocator, .{ .name = "href", .value = "https://example.com" });
    defer parent_node.deinit(allocator);

    var child_node = dom.Node.init(allocator, .element);
    child_node.tag = .span;
    child_node.parent = &parent_node;
    try parent_node.children.append(allocator, &child_node);

    const style = properties.ComputedStyle{};
    const sn = resolver.StyledNode{
        .node = &child_node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 200, .height = 50 };
    defer root.deinit(allocator);

    var handler = interaction.InteractionHandler{};
    const result = handler.handleClick(&root, 10, 10, 0);
    try std.testing.expect(result.href != null);
    try std.testing.expectEqualStrings("https://example.com", result.href.?);
    try std.testing.expect(result.target_node != null);
}

test "Click miss returns no target" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    node.tag = .div;
    defer node.deinit(allocator);

    const style = properties.ComputedStyle{};
    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 50, .height = 50 };
    defer root.deinit(allocator);

    var handler = interaction.InteractionHandler{};
    const result = handler.handleClick(&root, 999, 999, 0);
    try std.testing.expect(result.href == null);
    try std.testing.expect(result.target_node == null);
}
