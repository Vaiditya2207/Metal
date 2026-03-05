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
        layoutInlineBlock(box, parent_fs, ctx.allocator);
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
        if (w.unit == .auto) null else layout.resolveLength(w, cb_width, ctx, style.font_size.value)
    else
        null;

    var margin_left = layout.resolveLength(style.margin_left, cb_width, ctx, style.font_size.value);
    var margin_right = layout.resolveLength(style.margin_right, cb_width, ctx, style.font_size.value);
    const padding_left = layout.resolveLength(style.padding_left, cb_width, ctx, style.font_size.value);
    const padding_right = layout.resolveLength(style.padding_right, cb_width, ctx, style.font_size.value);
    const border_left = layout.resolveLength(style.border_width, cb_width, ctx, style.font_size.value);
    const border_right = layout.resolveLength(style.border_width, cb_width, ctx, style.font_size.value);

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
        const min_w = layout.resolveLength(mw, cb_width, ctx, style.font_size.value);
        if (style.box_sizing == .border_box) {
            const horizontal_extras = padding_left + padding_right + border_left + border_right;
            box.dimensions.content.width = @max(box.dimensions.content.width, @max(0, min_w - horizontal_extras));
        } else {
            box.dimensions.content.width = @max(box.dimensions.content.width, min_w);
        }
    }

    if (style.max_width) |mw| {
        const max_w = layout.resolveLength(mw, cb_width, ctx, style.font_size.value);
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

    box.dimensions.margin.top = layout.resolveLength(style.margin_top, cb_width, ctx, style.font_size.value);
    box.dimensions.margin.bottom = layout.resolveLength(style.margin_bottom, cb_width, ctx, style.font_size.value);
    box.dimensions.padding.top = layout.resolveLength(style.padding_top, cb_width, ctx, style.font_size.value);
    box.dimensions.padding.bottom = layout.resolveLength(style.padding_bottom, cb_width, ctx, style.font_size.value);
    box.dimensions.border.top = layout.resolveLength(style.border_width, cb_width, ctx, style.font_size.value);
    box.dimensions.border.bottom = layout.resolveLength(style.border_width, cb_width, ctx, style.font_size.value);

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

/// Recursively shift a box and ALL its descendants by `delta` in the Y direction.
fn shiftBoxY(box: *LayoutBox, delta: f32) void {
    box.dimensions.content.y += delta;
    for (box.children.items) |child| {
        shiftBoxY(child, delta);
    }
}

fn layoutChildren(box: *LayoutBox, ctx: layout.LayoutContext) void {
    box.dimensions.content.height = 0;
    
    var pending_margin: f32 = 0;
    var is_at_parent_top = true;
    
    const is_root = box.styled_node != null and box.styled_node.?.node.parent == null;
    const parent_can_collapse_top = (box.styled_node != null) and !is_root and
                                    box.dimensions.padding.top == 0 and
                                    box.dimensions.border.top == 0;
                                    
    const parent_can_collapse_bottom = (box.styled_node != null) and !is_root and
                                       box.dimensions.padding.bottom == 0 and
                                       box.dimensions.border.bottom == 0;

    for (box.children.items) |child| {
        const is_out_of_flow = if (child.styled_node) |sn|
            sn.style.position == .absolute or sn.style.position == .fixed
        else
            false;

        if (is_out_of_flow) {
            layoutBlock(child, box, ctx);
            position.applyPositioning(child, ctx);
            continue;
        }

        // Save the child's style-declared margin BEFORE layoutBlock.
        // layoutBlock calls calculatePosition (which uses this margin for positioning)
        // then layoutChildren (which may INCREASE the margin via grandchild collapsing).
        const original_child_mt = if (child.styled_node) |sn|
            layout.resolveLength(sn.style.margin_top, box.dimensions.content.width, ctx, sn.style.font_size.value)
        else
            @as(f32, 0);

        layoutBlock(child, box, ctx);

        // After layoutBlock, the child's margin.top may have been inflated
        // by its own children's margin collapsing. Use this updated value
        // for collapsing with OUR margin, but use original_child_mt for
        // position adjustments (since calculatePosition used that value).
        const child_mt = child.dimensions.margin.top;
        const child_mb = child.dimensions.margin.bottom;
        const child_content_h = child.dimensions.content.height;
        const child_bpt = child.dimensions.border.top + child.dimensions.padding.top;
        const child_bpb = child.dimensions.border.bottom + child.dimensions.padding.bottom;
        
        const child_is_empty = (child_content_h == 0 and child_bpt == 0 and child_bpb == 0);

        if (is_at_parent_top and parent_can_collapse_top) {
            // Parent-first-child margin collapsing (CSS2 §8.3.1):
            // The child's (possibly inflated) margin collapses with parent's margin.
            box.dimensions.margin.top = @max(box.dimensions.margin.top, child_mt);
            
            // Remove the ORIGINAL margin that calculatePosition used for positioning.
            // The collapsed margin is now handled by the parent's margin.top.
            // Must shift ALL descendants since they were positioned relative to old Y.
            shiftBoxY(child, -original_child_mt);
            
            if (child_is_empty) {
                // Empty element: top and bottom margins collapse through it
                box.dimensions.margin.top = @max(box.dimensions.margin.top, child_mb);
                // is_at_parent_top stays true
            } else {
                is_at_parent_top = false;
                box.dimensions.content.height += child_bpt + child_content_h + child_bpb;
                pending_margin = child_mb;
            }
        } else {
            // Sibling margin collapsing
            const collapsed = @max(pending_margin, child_mt);
            
            if (child_is_empty) {
                // Empty sibling: merge its margins into the pending chain
                pending_margin = @max(collapsed, child_mb);
            } else {
                // calculatePosition placed child using original_child_mt.
                // We want the gap to be `collapsed` instead.
                const adjustment = collapsed - original_child_mt;
                shiftBoxY(child, adjustment);
                
                box.dimensions.content.height += collapsed + child_bpt + child_content_h + child_bpb;
                pending_margin = child_mb;
                is_at_parent_top = false;
            }
        }
    }

    if (!is_at_parent_top) {
        if (parent_can_collapse_bottom) {
            box.dimensions.margin.bottom = @max(box.dimensions.margin.bottom, pending_margin);
        } else {
            box.dimensions.content.height += pending_margin;
        }
    }
}

fn calculateHeight(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    if (box.styled_node) |sn| {
        const cb_height = if (containing_block) |cb| cb.dimensions.content.height else ctx.viewport_height;

        if (sn.style.height) |h| {
            const height = layout.resolveLength(h, cb_height, ctx, sn.style.font_size.value);

            if (sn.style.box_sizing == .border_box) {
                const vertical_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                    box.dimensions.border.top + box.dimensions.border.bottom;
                box.dimensions.content.height = @max(0, height - vertical_extras);
            } else {
                box.dimensions.content.height = height;
            }
        }

        if (sn.style.min_height) |mh| {
            const min_h = layout.resolveLength(mh, cb_height, ctx, sn.style.font_size.value);
            if (sn.style.box_sizing == .border_box) {
                const vertical_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                    box.dimensions.border.top + box.dimensions.border.bottom;
                box.dimensions.content.height = @max(box.dimensions.content.height, @max(0, min_h - vertical_extras));
            } else {
                box.dimensions.content.height = @max(box.dimensions.content.height, min_h);
            }
        }

        if (sn.style.max_height) |mh| {
            const max_h = layout.resolveLength(mh, cb_height, ctx, sn.style.font_size.value);
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
