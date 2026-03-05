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
    box.dimensions.content.width = cb_width - style_margin.left - style_margin.right - style_border.left - style_border.right - style_padding.left - style_padding.right;

    // Position
    if (containing_block) |cb| {
        box.dimensions.content.x = cb.dimensions.content.x + style_margin.left + style_border.left + style_padding.left;
        box.dimensions.content.y = cb.dimensions.content.y + cb.dimensions.content.height + style_margin.top + style_border.top + style_padding.top;
    }

    // 2. Count columns
    var num_cols: usize = 0;
    for (box.children.items) |row| {
        if (row.box_type == .tableRowNode) {
            var cell_count: usize = 0;
            for (row.children.items) |cell| {
                if (cell.box_type == .tableCellNode) cell_count += 1;
            }
            if (cell_count > num_cols) num_cols = cell_count;
        }
    }

    const col_w = if (num_cols > 0) box.dimensions.content.width / @as(f32, @floatFromInt(num_cols)) else box.dimensions.content.width;

    var current_y: f32 = 0;

    for (box.children.items) |row| {
        if (row.box_type != .tableRowNode) continue;
        
        row.dimensions.content.width = box.dimensions.content.width;
        row.dimensions.content.x = box.dimensions.content.x;
        row.dimensions.content.y = box.dimensions.content.y + current_y;

        var current_x: f32 = 0;
        var row_height: f32 = 0;

        for (row.children.items) |cell| {
            if (cell.box_type != .tableCellNode) continue;

            // Fake containing block to force column width on the cell block layout
            var fake_cb = box_mod.LayoutBox.init(.blockNode, null);
            fake_cb.dimensions.content.width = col_w;
            fake_cb.dimensions.content.x = row.dimensions.content.x + current_x;
            fake_cb.dimensions.content.y = row.dimensions.content.y;
            
            block.layoutBlock(cell, &fake_cb, ctx);

            const cell_h = cell.dimensions.marginBox().height;
            if (cell_h > row_height) {
                row_height = cell_h;
            }

            current_x += col_w;
        }

        row.dimensions.content.height = row_height;
        current_y += row_height;
    }

    box.dimensions.content.height = current_y;
    
    // Apply layout accumulation to parent
    if (containing_block) |cb| {
        cb.dimensions.content.height += box.dimensions.marginBox().height;
    }
}
