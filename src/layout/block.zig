const LayoutBox = @import("box.zig").LayoutBox;
const layoutInlineBlock = @import("inline.zig").layoutInlineBlock;
const position = @import("position.zig");
const flex = @import("flex.zig");
const block_width = @import("block_width.zig");
const block_position = @import("block_position.zig");
const block_metrics = @import("block_metrics.zig");

const layout = @import("layout.zig");

pub fn layoutBlock(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    if (box.box_type == .flexNode) {
        flex.layoutFlexBox(box, containing_block, ctx);
        return;
    }
    if (box.box_type == .anonymousBlock) {
        if (containing_block) |cb| {
            box.dimensions.content.width = cb.dimensions.content.width;
        }
    }
    block_width.calculateWidth(box, containing_block, ctx);
    block_position.calculatePosition(box, containing_block, ctx);

    // For anonymous blocks, layout inline content immediately after positioning
    if (box.box_type == .anonymousBlock) {
        const parent_fs: f32 = if (containing_block) |cb| (if (cb.styled_node) |sn| sn.style.font_size.value else 16.0) else 16.0;
        layoutInlineBlock(box, parent_fs, ctx);
        // Important: return early since it has no block children to layout in layoutChildren
        return;
    }

    const locked_height = box.lock_content_height;
    const preserved_height = box.dimensions.content.height;
    layoutChildren(box, ctx);

    if (locked_height) {
        box.dimensions.content.height = preserved_height;
        // Still apply min-height/max-height constraints even when flex-locked.
        // The flex sizing pass sets the main-axis size but doesn't apply the
        // element's own min/max constraints (CSS Flexbox §4.5).
        if (box.styled_node) |sn| {
            const cb_height = if (containing_block) |cb| cb.dimensions.content.height else ctx.viewport_height;
            if (sn.style.min_height) |mh| {
                if (mh.unit != .percent and mh.unit != .calc) {
                    const min_h = layout.resolveLength(mh, cb_height, ctx, sn.style.font_size.value);
                    if (sn.style.box_sizing == .border_box) {
                        const v_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                            box.dimensions.border.top + box.dimensions.border.bottom;
                        box.dimensions.content.height = @max(box.dimensions.content.height, @max(0, min_h - v_extras));
                    } else {
                        box.dimensions.content.height = @max(box.dimensions.content.height, min_h);
                    }
                } else {
                    // For percentage/calc, only apply if cb_height > 0 (definite)
                    if (cb_height > 0) {
                        const min_h = layout.resolveLength(mh, cb_height, ctx, sn.style.font_size.value);
                        box.dimensions.content.height = @max(box.dimensions.content.height, min_h);
                    }
                }
            }
            if (sn.style.max_height) |mh| {
                if (mh.unit != .percent and mh.unit != .calc) {
                    const max_h = layout.resolveLength(mh, cb_height, ctx, sn.style.font_size.value);
                    if (sn.style.box_sizing == .border_box) {
                        const v_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                            box.dimensions.border.top + box.dimensions.border.bottom;
                        box.dimensions.content.height = @min(box.dimensions.content.height, @max(0, max_h - v_extras));
                    } else {
                        box.dimensions.content.height = @min(box.dimensions.content.height, max_h);
                    }
                } else {
                    // For percentage/calc, only apply if cb_height > 0 (definite)
                    if (cb_height > 0) {
                        const max_h = layout.resolveLength(mh, cb_height, ctx, sn.style.font_size.value);
                        box.dimensions.content.height = @min(box.dimensions.content.height, max_h);
                    }
                }
            }
        }
    } else {
        block_metrics.calculateHeight(box, containing_block, ctx);
    }

    // CSS 2.1 §10.3.9: inline-block with auto width uses shrink-to-fit.
    // CSS 2.1 §10.3.5: floated blocks with auto width also use shrink-to-fit.
    // After children are laid out, shrink width to actual content extent.
    const is_float = if (box.styled_node) |sn| sn.style.float != .none else false;
    if (box.box_type == .inlineBlockNode or is_float) {
        if (box.styled_node) |sn| {
            const has_explicit_width = sn.style.width != null and sn.style.width.?.unit != .auto;
            if (!has_explicit_width and !box.lock_content_width) {
                const max_right = measureContentExtent(box);
                if (max_right > 0 and max_right < box.dimensions.content.width) {
                    box.dimensions.content.width = max_right;
                }
                // Apply min-width / max-width after shrink-to-fit (CSS 2.1 §10.3.5)
                if (sn.style.min_width) |mw| {
                    var min_w = layout.resolveLength(mw, box.dimensions.content.width, ctx, sn.style.font_size.value);
                    if (sn.style.box_sizing == .border_box) {
                        const h_extras = box.dimensions.padding.left + box.dimensions.padding.right +
                            box.dimensions.border.left + box.dimensions.border.right;
                        min_w = @max(0, min_w - h_extras);
                    }
                    box.dimensions.content.width = @max(box.dimensions.content.width, min_w);
                }
                if (sn.style.max_width) |mw| {
                    var max_w = layout.resolveLength(mw, box.dimensions.content.width, ctx, sn.style.font_size.value);
                    if (sn.style.box_sizing == .border_box) {
                        const h_extras = box.dimensions.padding.left + box.dimensions.padding.right +
                            box.dimensions.border.left + box.dimensions.border.right;
                        max_w = @max(0, max_w - h_extras);
                    }
                    box.dimensions.content.width = @min(box.dimensions.content.width, max_w);
                }

                // Re-layout children with the shrunk width so that inline content
                // (text-align, line breaks) reflows correctly within the narrower box.
                // The lock_content_width flag prevents calculateWidth from overwriting
                // the shrunk width during the second pass.
                box.lock_content_width = true;
                layoutChildren(box, ctx);
                box.lock_content_width = false;

                // RC-30: Re-apply explicit CSS height after shrink-to-fit re-layout.
                // layoutChildren resets content.height to 0, destroying any explicit
                // height that calculateHeight set earlier in this function.
                if (!box.lock_content_height) {
                    block_metrics.calculateHeight(box, containing_block, ctx);
                }
            }
        }
    }

    // Apply relative positioning last for normal flow elements
    if (box.styled_node) |sn| {
        if (sn.style.position == .relative) {
            position.applyPositioning(box, ctx);
        }
    }
}

fn layoutChildren(box: *LayoutBox, ctx: layout.LayoutContext) void {
    box.dimensions.content.height = 0;

    var pending_margin: f32 = 0;
    var is_at_parent_top = true;

    const is_root = box.styled_node != null and box.styled_node.?.node.parent == null;

    // BFC-establishing elements suppress parent-child margin collapsing
    const is_bfc = box.is_bfc or box.box_type == .flexNode or box.box_type == .inlineBlockNode or
        (if (box.styled_node) |sn| sn.style.float != .none else false);

    const parent_can_collapse_top = !is_bfc and (box.styled_node != null) and !is_root and
        box.dimensions.padding.top == 0 and
        box.dimensions.border.top == 0;

    const parent_can_collapse_bottom = !is_bfc and (box.styled_node != null) and !is_root and
        box.dimensions.padding.bottom == 0 and
        box.dimensions.border.bottom == 0;

    for (box.children.items) |child| {
        const is_out_of_flow = if (child.styled_node) |sn|
            sn.style.position == .absolute or sn.style.position == .fixed
        else
            false;

        if (is_out_of_flow) {
            var abs_fc = layout.FloatContext.init(ctx.allocator);
            defer abs_fc.deinit();
            var abs_ctx = ctx;
            abs_ctx.float_ctx = &abs_fc;

            if (child.box_type == .tableNode) {
                @import("table.zig").layoutTable(child, box, abs_ctx);
            } else {
                layoutBlock(child, box, abs_ctx);
            }
            position.applyPositioning(child, abs_ctx);
            continue;
        }

        const is_floated = if (child.styled_node) |sn| sn.style.float != .none else false;

        // Handle clear
        if (child.styled_node) |sn| {
            if (sn.style.clear != .none) {
                if (ctx.float_ctx) |fc| {
                    const clear_y = fc.getClearY(sn.style.clear);
                    const absolute_parent_y = box.dimensions.content.y;
                    const relative_clear_y = clear_y - absolute_parent_y;
                    if (relative_clear_y > box.dimensions.content.height) {
                        box.dimensions.content.height = relative_clear_y;
                        pending_margin = 0; // clearing breaks margin collapsing
                    }
                }
            }
        }

        // Save the child's style-declared margin BEFORE layoutBlock.
        // layoutBlock calls calculatePosition (which uses this margin for positioning)
        // then layoutChildren (which may INCREASE the margin via grandchild collapsing).
        const original_child_mt = if (child.styled_node) |sn|
            layout.resolveLength(sn.style.margin_top, box.dimensions.content.width, ctx, sn.style.font_size.value)
        else if (child.box_type == .anonymousBlock)
            pending_margin
        else
            @as(f32, 0);

        if (child.box_type == .tableNode) {
            @import("table.zig").layoutTable(child, box, ctx);
        } else {
            layoutBlock(child, box, ctx);
        }

        if (is_floated) {
            if (ctx.float_ctx) |fc| {
                const rect = child.dimensions.borderBox();
                fc.addFloat(rect, if (child.styled_node.?.style.float == .left) .left else .right) catch {};
            }
            // Floats don't affect parent height or pending_margin in the same way
            continue;
        }

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
            block_metrics.shiftBoxY(child, -original_child_mt);

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
                block_metrics.shiftBoxY(child, adjustment);

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

/// Recursively measures the actual content extent (max right edge) of a layout box,
/// traversing into anonymous blocks to find their text_runs. Returns the maximum
/// right edge relative to the box's own content.x (i.e., the content width needed).
fn measureContentExtent(box: *LayoutBox) f32 {
    var max_right: f32 = 0;
    const origin = box.dimensions.content.x;

    for (box.children.items) |child| {
        if (child.box_type == .anonymousBlock) {
            const child_extent = measureContentExtent(child);
            max_right = @max(max_right, child_extent);
        } else {
            const child_margin_box = child.dimensions.marginBox();
            const right = child_margin_box.x + child_margin_box.width - origin;
            max_right = @max(max_right, right);
        }
    }

    // For text runs, compute extent as (max_right_edge - min_left_edge) to cancel
    // out any text-align alignment offsets. This gives the actual content span
    // regardless of centering or right-alignment shifts.
    if (box.text_runs.items.len > 0) {
        var min_x: f32 = box.text_runs.items[0].x;
        var max_text_right: f32 = box.text_runs.items[0].x + box.text_runs.items[0].width;
        for (box.text_runs.items[1..]) |run| {
            min_x = @min(min_x, run.x);
            max_text_right = @max(max_text_right, run.x + run.width);
        }
        max_right = @max(max_right, max_text_right - min_x);
    }

    return max_right;
}
