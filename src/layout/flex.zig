const std = @import("std");
const LayoutBox = @import("box.zig").LayoutBox;
const block = @import("block.zig");

const layout = @import("layout.zig");

pub fn layoutFlexBox(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    const style = if (box.styled_node) |sn| &sn.style else return;
    const cb_width = if (containing_block) |cb| cb.dimensions.content.width else box.dimensions.content.width;
    box.dimensions.content.width = if (style.width) |w| layout.resolveLength(w, cb_width, ctx) else cb_width;

    // Resolve container's own margin/padding/border
    box.dimensions.margin.left = layout.resolveLength(style.margin_left, cb_width, ctx);
    box.dimensions.margin.right = layout.resolveLength(style.margin_right, cb_width, ctx);
    box.dimensions.margin.top = layout.resolveLength(style.margin_top, cb_width, ctx);
    box.dimensions.margin.bottom = layout.resolveLength(style.margin_bottom, cb_width, ctx);
    box.dimensions.padding.left = layout.resolveLength(style.padding_left, cb_width, ctx);
    box.dimensions.padding.right = layout.resolveLength(style.padding_right, cb_width, ctx);
    box.dimensions.padding.top = layout.resolveLength(style.padding_top, cb_width, ctx);
    box.dimensions.padding.bottom = layout.resolveLength(style.padding_bottom, cb_width, ctx);
    box.dimensions.border.left = layout.resolveLength(style.border_width, cb_width, ctx);
    box.dimensions.border.right = layout.resolveLength(style.border_width, cb_width, ctx);
    box.dimensions.border.top = layout.resolveLength(style.border_width, cb_width, ctx);
    box.dimensions.border.bottom = layout.resolveLength(style.border_width, cb_width, ctx);

    // Subtract container's own padding/border from content width
    const h_extras = box.dimensions.padding.left + box.dimensions.padding.right + box.dimensions.border.left + box.dimensions.border.right;
    box.dimensions.content.width = @max(0, box.dimensions.content.width - h_extras);

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
        child.dimensions.margin.left = layout.resolveLength(c_style.margin_left, box.dimensions.content.width, ctx);
        child.dimensions.margin.right = layout.resolveLength(c_style.margin_right, box.dimensions.content.width, ctx);
        child.dimensions.margin.top = layout.resolveLength(c_style.margin_top, box.dimensions.content.width, ctx);
        child.dimensions.margin.bottom = layout.resolveLength(c_style.margin_bottom, box.dimensions.content.width, ctx);
        child.dimensions.padding.left = layout.resolveLength(c_style.padding_left, box.dimensions.content.width, ctx);
        child.dimensions.padding.right = layout.resolveLength(c_style.padding_right, box.dimensions.content.width, ctx);
        child.dimensions.padding.top = layout.resolveLength(c_style.padding_top, box.dimensions.content.width, ctx);
        child.dimensions.padding.bottom = layout.resolveLength(c_style.padding_bottom, box.dimensions.content.width, ctx);
        child.dimensions.border.left = layout.resolveLength(c_style.border_width, box.dimensions.content.width, ctx);
        child.dimensions.border.right = layout.resolveLength(c_style.border_width, box.dimensions.content.width, ctx);
        child.dimensions.border.top = layout.resolveLength(c_style.border_width, box.dimensions.content.width, ctx);
        child.dimensions.border.bottom = layout.resolveLength(c_style.border_width, box.dimensions.content.width, ctx);

        var base_size: f32 = 0;
        if (c_style.flex_basis) |fb| {
            base_size = layout.resolveLength(fb, if (is_row) box.dimensions.content.width else (if (style.height) |h| layout.resolveLength(h, ctx.viewport_height, ctx) else 0), ctx);
        } else if (is_row) {
            if (c_style.width) |w| base_size = layout.resolveLength(w, box.dimensions.content.width, ctx);
        } else {
            if (c_style.height) |h| base_size = layout.resolveLength(h, if (style.height) |sh| layout.resolveLength(sh, ctx.viewport_height, ctx) else 0, ctx);
        }

        base_sizes[i] = base_size;

        if (is_row) {
            child.dimensions.content.width = base_size;
        } else {
            child.dimensions.content.height = base_size;
            child.dimensions.content.width = box.dimensions.content.width - (child.dimensions.margin.left + child.dimensions.margin.right + child.dimensions.border.left + child.dimensions.border.right + child.dimensions.padding.left + child.dimensions.padding.right);
        }

        total_base_size += base_size + (if (is_row) (child.dimensions.margin.left + child.dimensions.margin.right + child.dimensions.border.left + child.dimensions.border.right + child.dimensions.padding.left + child.dimensions.padding.right) else (child.dimensions.margin.top + child.dimensions.margin.bottom + child.dimensions.border.top + child.dimensions.border.bottom + child.dimensions.padding.top + child.dimensions.padding.bottom));
        total_grow += c_style.flex_grow;
        total_shrink += c_style.flex_shrink;
    }

    const has_definite_main = is_row or style.height != null;
    const container_main_size = if (is_row) box.dimensions.content.width else (if (style.height) |h| layout.resolveLength(h, ctx.viewport_height, ctx) else 0);
    var available_space = container_main_size - total_base_size;

    if (available_space > 0 and total_grow > 0) {
        for (children.items) |child| {
            const c_style = if (child.styled_node) |sn| &sn.style else continue;
            const extra = (c_style.flex_grow / total_grow) * available_space;
            if (is_row) {
                child.dimensions.content.width += extra;
            } else {
                child.dimensions.content.height += extra;
            }
        }
        available_space = 0;
    }

    // Shrinking (only when container has a definite main size)
    if (available_space < 0 and total_shrink > 0 and has_definite_main) {
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
                } else {
                    child.dimensions.content.height -= shrink_amount;
                }
            }
            available_space = 0;
        }
    }

    // Positioning (Main Axis)
    var main_pos: f32 = 0;
    var spacing: f32 = 0;
    if (available_space > 0) {
        switch (style.justify_content) {
            .flex_start => {},
            .flex_end => main_pos = available_space,
            .center => main_pos = available_space / 2,
            .space_between => {
                if (children.items.len > 1) {
                    spacing = available_space / @as(f32, @floatFromInt(children.items.len - 1));
                }
            },
        }
    }

    var max_cross_size: f32 = 0;
    for (children.items) |child| {
        const c_style = if (child.styled_node) |sn| &sn.style else continue;

        if (is_row) {
            child.dimensions.content.y = box.dimensions.content.y + child.dimensions.margin.top + child.dimensions.border.top + child.dimensions.padding.top;
            child.dimensions.content.x = box.dimensions.content.x + main_pos + child.dimensions.margin.left + child.dimensions.border.left + child.dimensions.padding.left;
            main_pos += child.dimensions.marginBox().width + spacing;
        } else {
            child.dimensions.content.y = box.dimensions.content.y + main_pos + child.dimensions.margin.top + child.dimensions.border.top + child.dimensions.padding.top;
            child.dimensions.content.x = box.dimensions.content.x + child.dimensions.margin.left + child.dimensions.border.left + child.dimensions.padding.left;
            main_pos += child.dimensions.marginBox().height + spacing;
        }

        const container_cross_size = if (is_row) (if (style.height) |h| layout.resolveLength(h, ctx.viewport_height, ctx) else 0) else box.dimensions.content.width;
        if (is_row) {
            if (c_style.height) |h| child.dimensions.content.height = layout.resolveLength(h, container_cross_size, ctx);
        } else {
            if (c_style.width) |w| child.dimensions.content.width = layout.resolveLength(w, container_cross_size, ctx);
        }

        var cross_size = if (is_row) child.dimensions.marginBox().height else child.dimensions.marginBox().width;
        if (style.align_items == .stretch and container_cross_size > 0) {
            if (is_row) {
                if (c_style.height == null) {
                    child.dimensions.content.height = container_cross_size - (child.dimensions.margin.top + child.dimensions.margin.bottom + child.dimensions.border.top + child.dimensions.border.bottom + child.dimensions.padding.top + child.dimensions.padding.bottom);
                    cross_size = container_cross_size;
                }
            } else {
                if (c_style.width == null) {
                    child.dimensions.content.width = container_cross_size - (child.dimensions.margin.left + child.dimensions.margin.right + child.dimensions.border.left + child.dimensions.border.right + child.dimensions.padding.left + child.dimensions.padding.right);
                    cross_size = container_cross_size;
                }
            }
        }

        max_cross_size = @max(max_cross_size, cross_size);
        const child_full_cross_size = if (is_row) child.dimensions.marginBox().height else child.dimensions.marginBox().width;
        const cross_offset = switch (style.align_items) {
            .flex_start, .stretch => @as(f32, 0),
            .flex_end => container_cross_size - child_full_cross_size,
            .center => (container_cross_size - child_full_cross_size) / 2.0,
        };

        if (is_row) {
            child.dimensions.content.y += cross_offset;
        } else {
            child.dimensions.content.x += cross_offset;
        }
    }

    // Recurse into flex item children
    for (children.items) |child| {
        child.dimensions.content.height = 0;
        for (child.children.items) |grandchild| {
            block.layoutBlock(grandchild, child, ctx);
            child.dimensions.content.height += grandchild.dimensions.marginBox().height;
        }
    }

    // Recompute max_cross_size after children have their actual dimensions
    max_cross_size = 0;
    for (children.items) |child| {
        const actual_cross = if (is_row) child.dimensions.marginBox().height else child.dimensions.marginBox().width;
        max_cross_size = @max(max_cross_size, actual_cross);
    }

    if (style.height == null) {
        if (is_row) {
            box.dimensions.content.height = max_cross_size;
        } else {
            box.dimensions.content.height = main_pos;
        }
    } else {
        box.dimensions.content.height = layout.resolveLength(style.height, ctx.viewport_height, ctx);
    }
}
