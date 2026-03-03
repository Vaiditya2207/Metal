const std = @import("std");
const box_mod = @import("box.zig");
const text_measure = @import("text_measure.zig");

pub fn layoutInlineBlock(layout_box: *box_mod.LayoutBox, parent_font_size: f32) void {
    const available_width = layout_box.dimensions.content.width;
    const space_width: f32 = text_measure.measureTextWidth(" ", parent_font_size);
    var cursor_x: f32 = 0;
    var cursor_y: f32 = 0;
    var current_line_height: f32 = parent_font_size * 1.2;

    for (layout_box.children.items) |child| {
        const child_font_size: f32 = if (child.styled_node) |sn|
            sn.style.font_size.value
        else
            parent_font_size;
        const child_line_height: f32 = child_font_size * 1.2;

        const text = blk: {
            if (child.styled_node) |sn| {
                if (sn.node.node_type == .text) {
                    break :blk sn.node.data orelse "";
                }
            }
            break :blk "";
        };

        if (text.len == 0) {
            child.dimensions.content.x = layout_box.dimensions.content.x + cursor_x;
            child.dimensions.content.y = layout_box.dimensions.content.y + cursor_y;
            child.dimensions.content.width = 0;
            child.dimensions.content.height = child_line_height;
            current_line_height = @max(current_line_height, child_line_height);
            continue;
        }

        var child_x: f32 = cursor_x;
        var child_y: f32 = cursor_y;
        var placed = false;

        var iter = std.mem.splitAny(u8, text, " \t\n\r");
        var first_word = true;
        while (iter.next()) |word| {
            if (word.len == 0) continue;
            const word_width = text_measure.measureTextWidth(word, child_font_size);

            if (!first_word and cursor_x > 0) {
                cursor_x += space_width;
            }

            if (cursor_x + word_width > available_width and cursor_x > 0) {
                cursor_x = 0;
                cursor_y += current_line_height;
                current_line_height = child_line_height;
            }

            if (!placed) {
                child_x = cursor_x;
                child_y = cursor_y;
                placed = true;
            }

            cursor_x += word_width;
            first_word = false;
            current_line_height = @max(current_line_height, child_line_height);
        }

        child.dimensions.content.x = layout_box.dimensions.content.x + child_x;
        child.dimensions.content.y = layout_box.dimensions.content.y + child_y;
        child.dimensions.content.width = text_measure.measureTextWidth(text, child_font_size);
        child.dimensions.content.height = if (cursor_y > child_y)
            cursor_y - child_y + child_line_height
        else
            child_line_height;
    }

    if (layout_box.children.items.len > 0) {
        layout_box.dimensions.content.height = cursor_y + current_line_height;
    }
}
