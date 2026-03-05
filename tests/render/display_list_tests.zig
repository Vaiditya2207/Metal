const std = @import("std");
const layout_box = @import("../../src/layout/box.zig");
const properties = @import("../../src/css/properties.zig");
const values = @import("../../src/css/values.zig");
const resolver = @import("../../src/css/resolver.zig");
const dom = @import("../../src/dom/mod.zig");
const display_list = @import("../../src/render/display_list.zig");

test "build empty display list" {
    const allocator = std.testing.allocator;
    var root = layout_box.LayoutBox.init(.blockNode, null);
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    try std.testing.expectEqual(@as(usize, 0), dl.commands.items.len);
}

test "build display list with background color" {
    const allocator = std.testing.allocator;

    var node = dom.Node.init(allocator, .element);
    // No deinit method on Node, it uses an arena in real usage but here we just have empty lists

    const style = properties.ComputedStyle{
        .background_color = values.CssColor.fromRgb(255, 0, 0),
    };

    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 100, .height = 100 };
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    try std.testing.expect(dl.commands.items.len > 0);
    const cmd = dl.commands.items[0];
    switch (cmd) {
        .draw_rect => |rect| {
            try std.testing.expectEqual(@as(f32, 0), rect.rect.x);
            try std.testing.expectEqual(@as(f32, 0), rect.rect.y);
            try std.testing.expectEqual(@as(f32, 100), rect.rect.width);
            try std.testing.expectEqual(@as(f32, 100), rect.rect.height);
            try std.testing.expectEqual(@as(u8, 255), rect.color.r);
        },
        else => return error.UnexpectedCommand,
    }
}

test "overflow clip emission" {
    const allocator = std.testing.allocator;

    var node = dom.Node.init(allocator, .element);
    const style_hidden = properties.ComputedStyle{
        .overflow = .hidden,
    };

    const sn_hidden = resolver.StyledNode{
        .node = &node,
        .style = style_hidden,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn_hidden);
    root.dimensions.content = .{ .x = 10, .y = 10, .width = 100, .height = 100 };
    defer root.deinit(allocator);

    // Add a child
    var child_node = dom.Node.init(allocator, .element);
    const child_style = properties.ComputedStyle{};
    const child_sn = resolver.StyledNode{
        .node = &child_node,
        .style = child_style,
        .children = &.{},
    };
    var child = try allocator.create(layout_box.LayoutBox);
    child.* = layout_box.LayoutBox.init(.blockNode, &child_sn);
    child.dimensions.content = .{ .x = 10, .y = 10, .width = 200, .height = 200 };
    try root.children.append(allocator, child);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    // Expect: push_clip, background (for root), draw_rect (for child), pop_clip
    // Wait, background is drawn before push_clip according to the instructions
    // "After drawing background and text (existing code), but BEFORE iterating children"
    // "If so, emit a push_clip command with box.dimensions.paddingBox()"

    // Let's count commands
    var found_push = false;
    var found_pop = false;
    for (dl.commands.items) |cmd| {
        if (cmd == .push_clip) found_push = true;
        if (cmd == .pop_clip) found_pop = true;
    }
    try std.testing.expect(found_push);
    try std.testing.expect(found_pop);
}

test "no clip for overflow visible" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{ .overflow = .visible };
    const sn = resolver.StyledNode{ .node = &node, .style = style, .children = &.{} };
    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    for (dl.commands.items) |cmd| {
        if (cmd == .push_clip or cmd == .pop_clip) return error.UnexpectedClip;
    }
}

test "opacity multiplication" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{
        .background_color = values.CssColor.fromRgb(255, 255, 255),
        .opacity = 0.5,
    };
    const sn = resolver.StyledNode{ .node = &node, .style = style, .children = &.{} };
    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    const cmd = dl.commands.items[0];
    switch (cmd) {
        .draw_rect => |rect| {
            // 255 * 0.5 = 127.5, floor/int cast usually 127
            try std.testing.expect(rect.color.a < 255);
            try std.testing.expect(rect.color.a >= 127);
        },
        else => return error.UnexpectedCommand,
    }
}

test "opacity 0.0 results in alpha 0" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{
        .background_color = values.CssColor.fromRgb(255, 255, 255),
        .opacity = 0.0,
    };
    const sn = resolver.StyledNode{ .node = &node, .style = style, .children = &.{} };
    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    try std.testing.expect(dl.commands.items.len > 0);
    const cmd = dl.commands.items[0];
    switch (cmd) {
        .draw_rect => |rect| {
            try std.testing.expectEqual(@as(u8, 0), rect.color.a);
        },
        else => return error.UnexpectedCommand,
    }
}
