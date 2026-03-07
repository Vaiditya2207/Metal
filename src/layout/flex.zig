const std = @import("std");
const LayoutBox = @import("box.zig").LayoutBox;
const block = @import("block.zig");
const block_metrics = @import("block_metrics.zig");

const layout = @import("layout.zig");

const FlexLine = struct {
    start: usize,
    end: usize,
    main_size: f32,
    cross_size: f32,
};

fn moveSubtreeTo(child: *LayoutBox, target_x: f32, target_y: f32) void {
    const dx = target_x - child.dimensions.content.x;
    const dy = target_y - child.dimensions.content.y;
    if (dx != 0) block_metrics.shiftBoxX(child, dx);
    if (dy != 0) block_metrics.shiftBoxY(child, dy);
}

pub fn layoutFlexBox(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    const style = if (box.styled_node) |sn| &sn.style else return;
    const cb_width = if (containing_block) |cb| cb.dimensions.content.width else box.dimensions.content.width;
    const specified_w = if (style.width) |w| layout.resolveLength(w, cb_width, ctx, style.font_size.value) else cb_width;

    // Resolve container's own margin/padding/border
    box.dimensions.margin.left = layout.resolveLength(style.margin_left, cb_width, ctx, style.font_size.value);
    box.dimensions.margin.right = layout.resolveLength(style.margin_right, cb_width, ctx, style.font_size.value);
    box.dimensions.margin.top = layout.resolveLength(style.margin_top, cb_width, ctx, style.font_size.value);
    box.dimensions.margin.bottom = layout.resolveLength(style.margin_bottom, cb_width, ctx, style.font_size.value);
    box.dimensions.padding.left = layout.resolveLength(style.padding_left, cb_width, ctx, style.font_size.value);
    box.dimensions.padding.right = layout.resolveLength(style.padding_right, cb_width, ctx, style.font_size.value);
    box.dimensions.padding.top = layout.resolveLength(style.padding_top, cb_width, ctx, style.font_size.value);
    box.dimensions.padding.bottom = layout.resolveLength(style.padding_bottom, cb_width, ctx, style.font_size.value);
    box.dimensions.border.left = layout.resolveLength(style.border_width, cb_width, ctx, style.font_size.value);
    box.dimensions.border.right = layout.resolveLength(style.border_width, cb_width, ctx, style.font_size.value);
    box.dimensions.border.top = layout.resolveLength(style.border_width, cb_width, ctx, style.font_size.value);
    box.dimensions.border.bottom = layout.resolveLength(style.border_width, cb_width, ctx, style.font_size.value);

    // Subtract container's own padding/border from content width if border-box
    const h_extras = box.dimensions.padding.left + box.dimensions.padding.right + box.dimensions.border.left + box.dimensions.border.right;
    box.dimensions.content.width = @max(0, specified_w - h_extras);

    if (containing_block) |cb| {
        box.dimensions.content.x = cb.dimensions.content.x +
            box.dimensions.margin.left + box.dimensions.border.left + box.dimensions.padding.left;
        box.dimensions.content.y = cb.dimensions.content.y + cb.dimensions.content.height +
            box.dimensions.margin.top + box.dimensions.border.top + box.dimensions.padding.top;
    } else {
        box.dimensions.content.x = box.dimensions.margin.left + box.dimensions.border.left + box.dimensions.padding.left;
        box.dimensions.content.y = box.dimensions.margin.top + box.dimensions.border.top + box.dimensions.padding.top;
    }

    const is_row = style.flex_direction == .row;
    const container_main_size = if (is_row)
        box.dimensions.content.width
    else if (style.height) |h|
        layout.resolveLength(h, ctx.viewport_height, ctx, style.font_size.value)
    else
        0;
    const main_gap = if (is_row)
        @max(0, layout.resolveLength(style.column_gap, box.dimensions.content.width, ctx, style.font_size.value))
    else
        @max(0, layout.resolveLength(style.row_gap, container_main_size, ctx, style.font_size.value));
    const cross_gap = if (is_row)
        @max(0, layout.resolveLength(style.row_gap, ctx.viewport_height, ctx, style.font_size.value))
    else
        @max(0, layout.resolveLength(style.column_gap, box.dimensions.content.width, ctx, style.font_size.value));
    const wraps_main_axis = style.flex_wrap == .wrap and is_row and container_main_size > 0;

    var children = std.ArrayListUnmanaged(*LayoutBox){};
    defer children.deinit(ctx.allocator);

    for (box.children.items) |child| {
        const is_out_of_flow = if (child.styled_node) |sn|
            sn.style.position == .absolute or sn.style.position == .fixed
        else
            false;
        if (!is_out_of_flow) children.append(ctx.allocator, child) catch {};
    }

    var total_base_size: f32 = 0;
    var total_grow: f32 = 0;
    var total_shrink: f32 = 0;

    const base_sizes = ctx.allocator.alloc(f32, children.items.len) catch return;
    defer ctx.allocator.free(base_sizes);

    for (children.items, 0..) |child, i| {
        const c_style = if (child.styled_node) |sn| &sn.style else continue;
        child.dimensions.margin.left = layout.resolveLength(c_style.margin_left, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.margin.right = layout.resolveLength(c_style.margin_right, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.margin.top = layout.resolveLength(c_style.margin_top, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.margin.bottom = layout.resolveLength(c_style.margin_bottom, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.padding.left = layout.resolveLength(c_style.padding_left, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.padding.right = layout.resolveLength(c_style.padding_right, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.padding.top = layout.resolveLength(c_style.padding_top, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.padding.bottom = layout.resolveLength(c_style.padding_bottom, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.border.left = layout.resolveLength(c_style.border_width, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.border.right = layout.resolveLength(c_style.border_width, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.border.top = layout.resolveLength(c_style.border_width, box.dimensions.content.width, ctx, c_style.font_size.value);
        child.dimensions.border.bottom = layout.resolveLength(c_style.border_width, box.dimensions.content.width, ctx, c_style.font_size.value);

        var base_size: f32 = 0;
        if (c_style.flex_basis) |fb| {
            base_size = layout.resolveLength(fb, if (is_row) box.dimensions.content.width else container_main_size, ctx, c_style.font_size.value);
        } else if (is_row) {
            if (c_style.width) |w| base_size = layout.resolveLength(w, box.dimensions.content.width, ctx, c_style.font_size.value);
        } else {
            if (c_style.height) |h| base_size = layout.resolveLength(h, container_main_size, ctx, c_style.font_size.value);
        }

        const c_h_extras = child.dimensions.padding.left + child.dimensions.padding.right + child.dimensions.border.left + child.dimensions.border.right;
        const c_v_extras = child.dimensions.padding.top + child.dimensions.padding.bottom + child.dimensions.border.top + child.dimensions.border.bottom;

        base_sizes[i] = base_size;

        if (is_row) {
            if (c_style.box_sizing == .border_box) {
                child.dimensions.content.width = @max(0, base_size - c_h_extras);
            } else {
                child.dimensions.content.width = base_size;
            }
        } else {
            if (c_style.box_sizing == .border_box) {
                child.dimensions.content.height = @max(0, base_size - c_v_extras);
            } else {
                child.dimensions.content.height = base_size;
            }
            child.dimensions.content.width = box.dimensions.content.width - (child.dimensions.margin.left + child.dimensions.margin.right + child.dimensions.border.left + child.dimensions.border.right + child.dimensions.padding.left + child.dimensions.padding.right);
        }

        const margin_main = if (is_row) (child.dimensions.margin.left + child.dimensions.margin.right) else (child.dimensions.margin.top + child.dimensions.margin.bottom);
        const extras_main = if (is_row) c_h_extras else c_v_extras;

        if (c_style.box_sizing == .border_box) {
            total_base_size += base_size + margin_main;
        } else {
            total_base_size += base_size + extras_main + margin_main;
        }
        total_grow += c_style.flex_grow;
        total_shrink += c_style.flex_shrink;
    }

    if (children.items.len > 1) {
        total_base_size += main_gap * @as(f32, @floatFromInt(children.items.len - 1));
    }

    const has_definite_main = is_row or style.height != null;
    var available_space = container_main_size - total_base_size;

    if (available_space > 0 and total_grow > 0 and !wraps_main_axis) {
        for (children.items) |child| {
            const c_style = if (child.styled_node) |sn| &sn.style else continue;
            const extra = (c_style.flex_grow / total_grow) * available_space;
            if (is_row) {
                child.dimensions.content.width += extra;
                child.lock_content_width = true;
            } else {
                child.dimensions.content.height += extra;
                child.lock_content_height = true;
            }
        }
        available_space = 0;
    }

    // Shrinking
    if (available_space < 0 and total_shrink > 0 and has_definite_main and !wraps_main_axis) {
        const overflow = -available_space;
        var total_weighted_shrink: f32 = 0;
        for (children.items, 0..) |child, i| {
            const c_style = if (child.styled_node) |sn| &sn.style else continue;
            total_weighted_shrink += c_style.flex_shrink * base_sizes[i];
        }
        if (total_weighted_shrink > 0) {
            for (children.items, 0..) |child, i| {
                const c_style = if (child.styled_node) |sn| &sn.style else continue;
                const shrink_amount = (c_style.flex_shrink * base_sizes[i] / total_weighted_shrink) * overflow;
                if (is_row) {
                    child.dimensions.content.width -= shrink_amount;
                    child.lock_content_width = true;
                } else {
                    child.dimensions.content.height -= shrink_amount;
                    child.lock_content_height = true;
                }
            }
            available_space = 0;
        }
    }

    // Lock base size when no grow/shrink pass ran; avoid block layout resetting
    // the main-axis size to normal block behavior.
    for (children.items) |child| {
        if (is_row) {
            child.lock_content_width = true;
        } else {
            child.lock_content_height = true;
        }
    }

    // Pass 2: Layout each child fully
    for (children.items) |child| {
        if (child.box_type == .flexNode) {
            layoutFlexBox(child, box, ctx);
        } else {
            block.layoutBlock(child, box, ctx);
        }
    }

    // Pass 3: Position children and resolve cross-axis alignment
    var max_cross_size: f32 = 0;
    const container_cross_size = if (is_row)
        if (style.height) |h| layout.resolveLength(h, ctx.viewport_height, ctx, style.font_size.value) else 0
    else
        box.dimensions.content.width;

    if (wraps_main_axis) {
        var lines = std.ArrayListUnmanaged(FlexLine){};
        defer lines.deinit(ctx.allocator);

        var line_start: usize = 0;
        var line_main: f32 = 0;
        var line_cross: f32 = 0;

        for (children.items, 0..) |child, i| {
            const child_main = child.dimensions.marginBox().width;
            const child_cross = child.dimensions.marginBox().height;
            const next_main = if (i > line_start) line_main + main_gap + child_main else line_main + child_main;

            if (i > line_start and next_main > container_main_size) {
                lines.append(ctx.allocator, .{
                    .start = line_start,
                    .end = i,
                    .main_size = line_main,
                    .cross_size = line_cross,
                }) catch return;
                line_start = i;
                line_main = child_main;
                line_cross = child_cross;
            } else {
                line_main = next_main;
                line_cross = @max(line_cross, child_cross);
            }
        }

        if (children.items.len > line_start) {
            lines.append(ctx.allocator, .{
                .start = line_start,
                .end = children.items.len,
                .main_size = line_main,
                .cross_size = line_cross,
            }) catch return;
        }

        var line_y: f32 = 0;
        for (lines.items, 0..) |line, line_idx| {
            const line_available = container_main_size - line.main_size;
            var line_main_pos: f32 = 0;
            var line_spacing: f32 = 0;
            if (line_available > 0) {
                switch (style.justify_content) {
                    .flex_start => {},
                    .flex_end => line_main_pos = line_available,
                    .center => line_main_pos = line_available / 2.0,
                    .space_between => {
                        const line_count = line.end - line.start;
                        if (line_count > 1) {
                            line_spacing = line_available / @as(f32, @floatFromInt(line_count - 1));
                        }
                    },
                }
            }

            var i = line.start;
            while (i < line.end) : (i += 1) {
                const child = children.items[i];
                const target_x = box.dimensions.content.x + line_main_pos + child.dimensions.margin.left + child.dimensions.border.left + child.dimensions.padding.left;
                const target_y = box.dimensions.content.y + line_y + child.dimensions.margin.top + child.dimensions.border.top + child.dimensions.padding.top;
                moveSubtreeTo(child, target_x, target_y);

                const child_full_cross_size = child.dimensions.marginBox().height;
                const cross_offset = switch (style.align_items) {
                    .flex_start, .stretch => @as(f32, 0),
                    .flex_end => line.cross_size - child_full_cross_size,
                    .center => (line.cross_size - child_full_cross_size) / 2.0,
                };
                if (cross_offset != 0) {
                    block_metrics.shiftBoxY(child, cross_offset);
                }

                line_main_pos += child.dimensions.marginBox().width;
                if (i + 1 < line.end) {
                    line_main_pos += main_gap + line_spacing;
                }
            }

            line_y += line.cross_size;
            if (line_idx + 1 < lines.items.len) {
                line_y += cross_gap;
            }
        }
        max_cross_size = line_y;
    } else {
        var main_pos: f32 = 0;
        var spacing: f32 = 0;
        if (available_space > 0) {
            switch (style.justify_content) {
                .flex_start => {},
                .flex_end => main_pos = available_space,
                .center => main_pos = available_space / 2.0,
                .space_between => {
                    if (children.items.len > 1) {
                        spacing = available_space / @as(f32, @floatFromInt(children.items.len - 1));
                    }
                },
            }
        }

        for (children.items, 0..) |child, i| {
            // Initial positioning based on main-axis
            if (is_row) {
                const target_x = box.dimensions.content.x + main_pos + child.dimensions.margin.left + child.dimensions.border.left + child.dimensions.padding.left;
                const target_y = box.dimensions.content.y + child.dimensions.margin.top + child.dimensions.border.top + child.dimensions.padding.top;
                moveSubtreeTo(child, target_x, target_y);
            } else {
                const target_y = box.dimensions.content.y + main_pos + child.dimensions.margin.top + child.dimensions.border.top + child.dimensions.padding.top;
                const target_x = box.dimensions.content.x + child.dimensions.margin.left + child.dimensions.border.left + child.dimensions.padding.left;
                moveSubtreeTo(child, target_x, target_y);
            }

            // Apply align-items cross-axis offset
            const child_full_cross_size = if (is_row) child.dimensions.marginBox().height else child.dimensions.marginBox().width;
            if (container_cross_size > 0) {
                const cross_offset = switch (style.align_items) {
                    .flex_start, .stretch => @as(f32, 0),
                    .flex_end => container_cross_size - child_full_cross_size,
                    .center => (container_cross_size - child_full_cross_size) / 2.0,
                };
                if (cross_offset != 0) {
                    if (is_row) {
                        block_metrics.shiftBoxY(child, cross_offset);
                    } else {
                        block_metrics.shiftBoxX(child, cross_offset);
                    }
                }
            }

            if (is_row) {
                main_pos += child.dimensions.marginBox().width;
            } else {
                main_pos += child.dimensions.marginBox().height;
            }
            if (i + 1 < children.items.len) {
                main_pos += main_gap + spacing;
            }

            max_cross_size = @max(max_cross_size, child_full_cross_size);
        }

        if (!is_row and style.height == null) {
            max_cross_size = main_pos;
        }
    }

    if (style.height == null) {
        if (is_row) {
            box.dimensions.content.height = max_cross_size;
        } else {
            box.dimensions.content.height = max_cross_size;
        }
    } else {
        box.dimensions.content.height = layout.resolveLength(style.height, ctx.viewport_height, ctx, style.font_size.value);
    }
}
