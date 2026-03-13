const std = @import("std");
const box_mod = @import("box.zig");
const LayoutBox = box_mod.LayoutBox;
const LayoutContext = @import("layout.zig").LayoutContext;
const block = @import("block.zig");

pub fn layoutTable(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: LayoutContext) void {
    // 1. Determine table width
    const cb_width = if (containing_block) |cb| cb.dimensions.content.width else box.dimensions.content.width;

    // For now, tables are basically block level wrappers
    // Apply padding/border/margin logic roughly (we should use calculateWidth but we'll do it manually)
    var style_padding = box_mod.EdgeSizes{};
    var style_margin = box_mod.EdgeSizes{};
    var style_border = box_mod.EdgeSizes{};

    if (box.styled_node) |sn| {
        const font_size = sn.style.font_size.value;
        const layout = @import("layout.zig");

        style_padding.left = layout.resolveLength(sn.style.padding_left, cb_width, ctx, font_size);
        style_padding.right = layout.resolveLength(sn.style.padding_right, cb_width, ctx, font_size);
        style_padding.top = layout.resolveLength(sn.style.padding_top, cb_width, ctx, font_size);
        style_padding.bottom = layout.resolveLength(sn.style.padding_bottom, cb_width, ctx, font_size);

        style_margin.left = layout.resolveLength(sn.style.margin_left, cb_width, ctx, font_size);
        style_margin.right = layout.resolveLength(sn.style.margin_right, cb_width, ctx, font_size);
        style_margin.top = layout.resolveLength(sn.style.margin_top, cb_width, ctx, font_size);
        style_margin.bottom = layout.resolveLength(sn.style.margin_bottom, cb_width, ctx, font_size);

        style_border.left = layout.resolveLength(sn.style.border_width, cb_width, ctx, font_size);
        style_border.right = layout.resolveLength(sn.style.border_width, cb_width, ctx, font_size);
        style_border.top = layout.resolveLength(sn.style.border_width, cb_width, ctx, font_size);
        style_border.bottom = layout.resolveLength(sn.style.border_width, cb_width, ctx, font_size);
    }

    box.dimensions.padding = style_padding;
    box.dimensions.margin = style_margin;
    box.dimensions.border = style_border;

    // Content width
    const h_extras = style_padding.left + style_padding.right + style_border.left + style_border.right;
    const specified_w = if (box.styled_node) |sn| (if (sn.style.width) |w| @import("layout.zig").resolveLength(w, cb_width, ctx, sn.style.font_size.value) else cb_width) else cb_width;

    if (box.styled_node) |sn| {
        if (sn.style.box_sizing == .border_box) {
            box.dimensions.content.width = @max(0, specified_w - h_extras);
        } else {
            box.dimensions.content.width = specified_w;
        }
    } else {
        box.dimensions.content.width = specified_w - h_extras;
    }

    // Position
    if (containing_block) |cb| {
        box.dimensions.content.x = cb.dimensions.content.x + style_margin.left + style_border.left + style_padding.left;
        box.dimensions.content.y = cb.dimensions.content.y + cb.dimensions.content.height + style_margin.top + style_border.top + style_padding.top;
    }

    // 2. Count columns by looking into rows (including those inside tbody/thead/tfoot)
    var num_cols: usize = 0;
    const Helper = struct {
        fn countCols(b: *LayoutBox, max_cols: *usize) void {
            for (b.children.items) |child| {
                if (child.box_type == .tableRowNode) {
                    var cell_count: usize = 0;
                    for (child.children.items) |cell| {
                        if (cell.box_type == .tableCellNode) cell_count += 1;
                    }
                    if (cell_count > max_cols.*) max_cols.* = cell_count;
                } else if (child.box_type == .blockNode) {
                    // Recurse into blocks (like tbody)
                    countCols(child, max_cols);
                }
            }
        }
    };
    Helper.countCols(box, &num_cols);

    const col_w = if (num_cols > 0) box.dimensions.content.width / @as(f32, @floatFromInt(num_cols)) else box.dimensions.content.width;

    const LayoutHelper = struct {
        fn layoutRows(self_box: *LayoutBox, b: *LayoutBox, y_offset: *f32, c_w: f32, c_ctx: LayoutContext) void {
            for (b.children.items) |child| {
                if (child.box_type == .tableRowNode) {
                    child.dimensions.content.width = self_box.dimensions.content.width;
                    child.dimensions.content.x = self_box.dimensions.content.x;
                    child.dimensions.content.y = self_box.dimensions.content.y + y_offset.*;

                    var current_x: f32 = 0;
                    var row_height: f32 = 0;

                    for (child.children.items) |cell| {
                        if (cell.box_type != .tableCellNode) continue;

                        var fake_cb = box_mod.LayoutBox.init(.blockNode, null);
                        fake_cb.dimensions.content.width = c_w;
                        fake_cb.dimensions.content.x = child.dimensions.content.x + current_x;
                        fake_cb.dimensions.content.y = child.dimensions.content.y;

                        block.layoutBlock(cell, &fake_cb, c_ctx);

                        const cell_h = cell.dimensions.marginBox().height;
                        if (cell_h > row_height) {
                            row_height = cell_h;
                        }

                        current_x += c_w;
                    }

                    child.dimensions.content.height = row_height;
                    y_offset.* += row_height;
                } else if (child.box_type == .blockNode) {
                    // Recurse into tbody/thead
                    layoutRows(self_box, child, y_offset, c_w, c_ctx);
                    // Also propagate the TBODY's own dimensions if it affects layout
                    child.dimensions.content.width = self_box.dimensions.content.width;
                    child.dimensions.content.x = self_box.dimensions.content.x;
                    // Note: This is simplified.
                }
            }
        }
    };

    var current_y: f32 = 0;
    LayoutHelper.layoutRows(box, box, &current_y, col_w, ctx);

    box.dimensions.content.height = current_y;

    // L-9 FIX: Removed direct parent height accumulation.
    // The parent's layoutChildren (block.zig) already accumulates
    // child heights including tables, so adding here double-counts.
}
