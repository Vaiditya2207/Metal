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
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 100, .height = 100 };
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
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 100, .height = 100 };
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

test "background texture emits draw_image command" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{};
    const sn = resolver.StyledNode{ .node = &node, .style = style, .children = &.{} };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 5, .y = 7, .width = 120, .height = 40 };
    root.background_texture = @ptrFromInt(1);
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    try std.testing.expect(dl.commands.items.len > 0);
    const cmd = dl.commands.items[0];
    switch (cmd) {
        .draw_image => |img| {
            try std.testing.expectEqual(@as(f32, 5), img.rect.x);
            try std.testing.expectEqual(@as(f32, 7), img.rect.y);
            try std.testing.expectEqual(@as(f32, 120), img.rect.width);
            try std.testing.expectEqual(@as(f32, 40), img.rect.height);
        },
        else => return error.UnexpectedCommand,
    }
}

test "background repeat-x tiles across box width" {
    const allocator = std.testing.allocator;
    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{
        .background_repeat = .repeat_x,
        .background_size = .auto,
    };
    const sn = resolver.StyledNode{ .node = &node, .style = style, .children = &.{} };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 25, .height = 10 };
    root.background_texture = @ptrFromInt(1);
    root.background_intrinsic_width = 10;
    root.background_intrinsic_height = 10;
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    // 25px wide area tiled with 10px image => 3 tiles (10 + 10 + 5)
    try std.testing.expectEqual(@as(usize, 3), dl.commands.items.len);
    for (dl.commands.items) |cmd| {
        switch (cmd) {
            .draw_image => {},
            else => return error.UnexpectedCommand,
        }
    }
}

// ── Visual correctness tests ────────────────────────────────────────────

test "transparent background emits no draw_rect" {
    const allocator = std.testing.allocator;

    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{
        .background_color = values.CssColor{ .r = 0, .g = 0, .b = 0, .a = 0 },
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

    try std.testing.expectEqual(@as(usize, 0), dl.commands.items.len);
}

test "background color RGBA is preserved in draw_rect" {
    const allocator = std.testing.allocator;

    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{
        .background_color = values.CssColor{ .r = 128, .g = 64, .b = 32, .a = 200 },
    };
    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 10, .y = 20, .width = 50, .height = 50 };
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    try std.testing.expect(dl.commands.items.len > 0);
    const cmd = dl.commands.items[0];
    switch (cmd) {
        .draw_rect => |rect| {
            try std.testing.expectEqual(@as(u8, 128), rect.color.r);
            try std.testing.expectEqual(@as(u8, 64), rect.color.g);
            try std.testing.expectEqual(@as(u8, 32), rect.color.b);
            try std.testing.expectEqual(@as(u8, 200), rect.color.a);
        },
        else => return error.UnexpectedCommand,
    }
}

test "semi-transparent opacity modifies alpha channel" {
    const allocator = std.testing.allocator;

    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{
        .background_color = values.CssColor.fromRgb(100, 100, 100),
        .opacity = 0.5,
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
            try std.testing.expectEqual(@as(u8, 100), rect.color.r);
            try std.testing.expectEqual(@as(u8, 100), rect.color.g);
            try std.testing.expectEqual(@as(u8, 100), rect.color.b);
            // 255 * 0.5 = 127.5 → @intFromFloat → 127
            try std.testing.expect(rect.color.a >= 127);
            try std.testing.expect(rect.color.a <= 128);
        },
        else => return error.UnexpectedCommand,
    }
}

test "visibility hidden emits no commands" {
    const allocator = std.testing.allocator;

    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{
        .background_color = values.CssColor.fromRgb(255, 0, 0),
        .visibility = .hidden,
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

    try std.testing.expectEqual(@as(usize, 0), dl.commands.items.len);
}

test "zero-size box emits no draw_rect" {
    const allocator = std.testing.allocator;

    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{
        .background_color = values.CssColor.fromRgb(255, 0, 0),
    };
    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 0, .height = 100 };
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    // borderBox().width == 0 (no padding/border), so no draw_rect emitted
    for (dl.commands.items) |cmd| {
        switch (cmd) {
            .draw_rect => return error.UnexpectedDrawRect,
            else => {},
        }
    }
}

test "border generates draw_rect commands with border color" {
    const allocator = std.testing.allocator;

    var node = dom.Node.init(allocator, .element);
    const style = properties.ComputedStyle{
        .background_color = values.CssColor{ .r = 0, .g = 0, .b = 0, .a = 0 }, // transparent, no bg
        .border_width = .{ .value = 2, .unit = .px },
        .border_color = values.CssColor{ .r = 0, .g = 0, .b = 0, .a = 255 },
    };
    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 10, .y = 10, .width = 100, .height = 50 };
    root.dimensions.border = .{ .top = 2, .right = 2, .bottom = 2, .left = 2 };
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    // Should have 4 border draw_rect commands (top, bottom, left, right)
    // No background draw_rect since bg is transparent
    try std.testing.expectEqual(@as(usize, 4), dl.commands.items.len);

    // Check the top border: height should be 2 (border_width.value)
    var found_top_border = false;
    for (dl.commands.items) |cmd| {
        switch (cmd) {
            .draw_rect => |rect| {
                if (rect.rect.height == 2 and rect.rect.width > 2) {
                    // This is a horizontal border (top or bottom)
                    found_top_border = true;
                    try std.testing.expectEqual(@as(u8, 0), rect.color.r);
                    try std.testing.expectEqual(@as(u8, 0), rect.color.g);
                    try std.testing.expectEqual(@as(u8, 0), rect.color.b);
                    try std.testing.expectEqual(@as(u8, 255), rect.color.a);
                }
            },
            else => {},
        }
    }
    try std.testing.expect(found_top_border);
}

test "input button text-align center positions text centrally" {
    const allocator = std.testing.allocator;

    // Create an input element node with a value attribute
    var node = dom.Node.init(allocator, .element);
    node.tag = .input;
    try node.setAttribute("value", "Search");
    defer {
        // Free the duped attribute strings
        for (node.attributes.items) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        node.attributes.deinit(allocator);
    }

    const style = properties.ComputedStyle{
        .text_align = .center,
        .font_size = .{ .value = 16.0, .unit = .px },
    };

    const sn = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    var root = layout_box.LayoutBox.init(.blockNode, &sn);
    root.dimensions.content = .{ .x = 0, .y = 0, .width = 200, .height = 30 };
    defer root.deinit(allocator);

    var dl = try display_list.buildDisplayList(allocator, &root, null);
    defer dl.deinit();

    // Find the draw_text command for the input value
    var found_text = false;
    for (dl.commands.items) |cmd| {
        switch (cmd) {
            .draw_text => |dt| {
                if (std.mem.eql(u8, dt.text, "Search")) {
                    found_text = true;
                    // "Search" = 6 chars, char_width = 16 * 0.6 = 9.6, tw = 57.6
                    // centered x = 0 + (200 - 57.6) / 2 = 71.2
                    // With left-align, x would be 0 + 4.0 = 4.0
                    // So centered x must be significantly greater than 4.0
                    try std.testing.expect(dt.rect.x > 50.0);
                    try std.testing.expect(dt.rect.x < 100.0);
                }
            },
            else => {},
        }
    }
    try std.testing.expect(found_text);
}
