const std = @import("std");
const LayoutBox = @import("box.zig").LayoutBox;
const EdgeSizes = @import("box.zig").EdgeSizes;
const layoutInlineBlock = @import("inline.zig").layoutInlineBlock;
const position = @import("position.zig");
const flex = @import("flex.zig");
const values = @import("../css/values.zig");

const layout = @import("layout.zig");

pub fn layoutBlock(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    if (box.box_type == .flexNode) {
        flex.layoutFlexBox(box, containing_block, ctx);
        return;
    }
    if (box.box_type == .anonymousBlock) {
        if (containing_block) |cb| {
            box.dimensions.content.width = cb.dimensions.content.width;
            box.dimensions.content.x = cb.dimensions.content.x;
            box.dimensions.content.y = cb.dimensions.content.y + cb.dimensions.content.height;
        }
        const parent_fs: f32 = if (containing_block) |cb| (if (cb.styled_node) |sn| sn.style.font_size.value else 16.0) else 16.0;
        layoutInlineBlock(box, parent_fs);
        return;
    }
    calculateWidth(box, containing_block, ctx);
    calculatePosition(box, containing_block, ctx);
    layoutChildren(box, ctx);
    calculateHeight(box, containing_block, ctx);

    // Apply relative positioning last for normal flow elements
    if (box.styled_node) |sn| {
        if (sn.style.position == .relative) {
            position.applyPositioning(box, ctx);
        }
    }
}

fn calculateWidth(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    const cb_width = if (containing_block) |cb| cb.dimensions.content.width else box.dimensions.content.width;

    const style = if (box.styled_node) |sn| &sn.style else {
        box.dimensions.content.width = cb_width;
        return;
    };

    const width = if (style.width) |w|
        if (w.unit == .auto) null else layout.resolveLength(w, cb_width, ctx)
    else
        null;

    var margin_left = layout.resolveLength(style.margin_left, cb_width, ctx);
    var margin_right = layout.resolveLength(style.margin_right, cb_width, ctx);
    const padding_left = layout.resolveLength(style.padding_left, cb_width, ctx);
    const padding_right = layout.resolveLength(style.padding_right, cb_width, ctx);
    const border_left = layout.resolveLength(style.border_width, cb_width, ctx);
    const border_right = layout.resolveLength(style.border_width, cb_width, ctx);

    const total_extras = margin_left + margin_right + padding_left + padding_right + border_left + border_right;

    if (width) |w| {
        if (style.box_sizing == .border_box) {
            const horizontal_extras = padding_left + padding_right + border_left + border_right;
            box.dimensions.content.width = @max(0, w - horizontal_extras);
        } else {
            box.dimensions.content.width = w;
        }
    } else {
        box.dimensions.content.width = @max(0, cb_width - total_extras);
    }

    if (style.min_width) |mw| {
        const min_w = layout.resolveLength(mw, cb_width, ctx);
        if (style.box_sizing == .border_box) {
            const horizontal_extras = padding_left + padding_right + border_left + border_right;
            box.dimensions.content.width = @max(box.dimensions.content.width, @max(0, min_w - horizontal_extras));
        } else {
            box.dimensions.content.width = @max(box.dimensions.content.width, min_w);
        }
    }

    if (style.max_width) |mw| {
        const max_w = layout.resolveLength(mw, cb_width, ctx);
        if (style.box_sizing == .border_box) {
            const horizontal_extras = padding_left + padding_right + border_left + border_right;
            box.dimensions.content.width = @min(box.dimensions.content.width, @max(0, max_w - horizontal_extras));
        } else {
            box.dimensions.content.width = @min(box.dimensions.content.width, max_w);
        }
    }

    // Auto margins handling (centering)
    const width_is_auto = if (style.width) |w| w.unit == .auto else true;
    if (!width_is_auto) {
        const current_content_width = box.dimensions.content.width;
        // Re-calculate used width with current resolved values (margins are 0 if auto)
        const used_width = margin_left + border_left + padding_left + current_content_width + padding_right + border_right + margin_right;
        const available_space = cb_width - used_width;

        if (available_space > 0) {
            const ml_auto = style.margin_left.unit == .auto;
            const mr_auto = style.margin_right.unit == .auto;

            if (ml_auto and mr_auto) {
                margin_left += available_space / 2.0;
                margin_right += available_space / 2.0;
            } else if (ml_auto) {
                margin_left += available_space;
            } else if (mr_auto) {
                margin_right += available_space;
            }
        }
    }

    box.dimensions.margin.left = margin_left;
    box.dimensions.margin.right = margin_right;
    box.dimensions.padding.left = padding_left;
    box.dimensions.padding.right = padding_right;
    box.dimensions.border.left = border_left;
    box.dimensions.border.right = border_right;
}

fn calculatePosition(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    const style = if (box.styled_node) |sn| &sn.style else {
        if (containing_block) |cb| {
            box.dimensions.content.x = cb.dimensions.content.x;
            box.dimensions.content.y = cb.dimensions.content.y;
        }
        return;
    };

    const cb_width = if (containing_block) |cb| cb.dimensions.content.width else box.dimensions.content.width;

    box.dimensions.margin.top = layout.resolveLength(style.margin_top, cb_width, ctx);
    box.dimensions.margin.bottom = layout.resolveLength(style.margin_bottom, cb_width, ctx);
    box.dimensions.padding.top = layout.resolveLength(style.padding_top, cb_width, ctx);
    box.dimensions.padding.bottom = layout.resolveLength(style.padding_bottom, cb_width, ctx);
    box.dimensions.border.top = layout.resolveLength(style.border_width, cb_width, ctx);
    box.dimensions.border.bottom = layout.resolveLength(style.border_width, cb_width, ctx);

    if (containing_block) |cb| {
        box.dimensions.content.x = cb.dimensions.content.x +
            box.dimensions.margin.left +
            box.dimensions.border.left +
            box.dimensions.padding.left;

        box.dimensions.content.y = cb.dimensions.content.y +
            cb.dimensions.content.height +
            box.dimensions.margin.top +
            box.dimensions.border.top +
            box.dimensions.padding.top;
    } else {
        // Root element positioning
        box.dimensions.content.x = box.dimensions.margin.left +
            box.dimensions.border.left +
            box.dimensions.padding.left;

        box.dimensions.content.y = box.dimensions.margin.top +
            box.dimensions.border.top +
            box.dimensions.padding.top;
    }
}

fn layoutChildren(box: *LayoutBox, ctx: layout.LayoutContext) void {
    box.dimensions.content.height = 0;
    var prev_margin_bottom: f32 = 0;
    var is_first_in_flow = true;

    for (box.children.items) |child| {
        const is_out_of_flow = if (child.styled_node) |sn|
            sn.style.position == .absolute or sn.style.position == .fixed
        else
            false;

        if (is_out_of_flow) {
            layoutBlock(child, box, ctx);
            position.applyPositioning(child, ctx);
        } else {
            layoutBlock(child, box, ctx);

            if (!is_first_in_flow) {
                const collapsed = @max(prev_margin_bottom, child.dimensions.margin.top);
                const overlap = prev_margin_bottom + child.dimensions.margin.top - collapsed;
                child.dimensions.content.y -= overlap;
                box.dimensions.content.height -= overlap;
            }
            is_first_in_flow = false;

            box.dimensions.content.height += child.dimensions.marginBox().height;
            prev_margin_bottom = child.dimensions.margin.bottom;
        }
    }
}

fn calculateHeight(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    if (box.styled_node) |sn| {
        const cb_height = if (containing_block) |cb| cb.dimensions.content.height else ctx.viewport_height;

        if (sn.style.height) |h| {
            const height = layout.resolveLength(h, cb_height, ctx);

            if (sn.style.box_sizing == .border_box) {
                const vertical_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                    box.dimensions.border.top + box.dimensions.border.bottom;
                box.dimensions.content.height = @max(0, height - vertical_extras);
            } else {
                box.dimensions.content.height = height;
            }
        }

        if (sn.style.min_height) |mh| {
            const min_h = layout.resolveLength(mh, cb_height, ctx);
            if (sn.style.box_sizing == .border_box) {
                const vertical_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                    box.dimensions.border.top + box.dimensions.border.bottom;
                box.dimensions.content.height = @max(box.dimensions.content.height, @max(0, min_h - vertical_extras));
            } else {
                box.dimensions.content.height = @max(box.dimensions.content.height, min_h);
            }
        }

        if (sn.style.max_height) |mh| {
            const max_h = layout.resolveLength(mh, cb_height, ctx);
            if (sn.style.box_sizing == .border_box) {
                const vertical_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                    box.dimensions.border.top + box.dimensions.border.bottom;
                box.dimensions.content.height = @min(box.dimensions.content.height, @max(0, max_h - vertical_extras));
            } else {
                box.dimensions.content.height = @min(box.dimensions.content.height, max_h);
            }
        }
    }
}
