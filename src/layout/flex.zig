const std = @import("std");
const LayoutBox = @import("box.zig").LayoutBox;
const block = @import("block.zig");
const block_metrics = @import("block_metrics.zig");

const layout = @import("layout.zig");
const position = @import("position.zig");
const values = @import("../css/values.zig");

/// Measures the intrinsic content width of a layout box — the minimum width
/// needed to contain all actual content (text runs, inline-blocks with explicit/
/// intrinsic sizes). Returns a width value, not a coordinate.
/// This ignores auto-margin centering offsets that distort positioned coordinates.
fn measureMaxContentRight(node: *LayoutBox, _: f32) f32 {
    // Use width-based measurement to avoid position distortions from margin:auto
    return measureIntrinsicWidth(node);
}

/// Measures intrinsic content width by summing content, padding, and border,
/// recursing into auto-width children. Ignores margin:auto positioning.
/// For row flex containers, children are side-by-side so their widths are
/// SUMMED; for block/column containers, the MAX is taken.
pub fn measureIntrinsicWidth(node: *LayoutBox) f32 {
    var max_width: f32 = 0;
    var sum_width: f32 = 0;

    // Detect row flex container: children are laid out side-by-side
    const is_row_flex = node.box_type == .flexNode and
        if (node.styled_node) |sn| sn.style.flex_direction == .row else false;

    // Detect anonymous block: wraps inline-level content that flows horizontally.
    // All children (inline, inline-block, text) sit on one line when unconstrained,
    // so the intrinsic width is the sum of all items, not the max.
    const is_inline_flow = node.box_type == .anonymousBlock;

    const should_sum = is_row_flex or is_inline_flow;

    // Check text runs — use their width directly (not position-dependent)
    // Text runs always use @max since they have absolute x positions
    for (node.text_runs.items) |run| {
        const run_right = (run.x - node.dimensions.content.x) + run.width;
        max_width = @max(max_width, run_right);
    }

    // Check children
    for (node.children.items) |child| {
        const c_style = if (child.styled_node) |sn| &sn.style else null;
        const has_explicit_width = if (c_style) |cs| cs.width != null else false;

        // Skip absolutely/fixed positioned children — they're out of flow
        const is_out_of_flow = if (c_style) |cs|
            cs.position == .absolute or cs.position == .fixed
        else
            false;
        if (is_out_of_flow) continue;

        const has_laid_out_width = child.box_type == .inlineBlockNode and child.dimensions.content.width > 0;
        if (has_explicit_width or child.intrinsic_width > 0 or has_laid_out_width) {
            // This child has an explicit/intrinsic width — use its full box width
            // (content + padding + border) plus non-auto margins
            var child_width = child.dimensions.content.width +
                child.dimensions.padding.left + child.dimensions.padding.right +
                child.dimensions.border.left + child.dimensions.border.right;
            // Only add margins that aren't auto (auto margins are centering artifacts)
            const ml_auto = if (c_style) |cs| cs.margin_left.unit == .auto else false;
            const mr_auto = if (c_style) |cs| cs.margin_right.unit == .auto else false;
            if (!ml_auto) child_width += child.dimensions.margin.left;
            if (!mr_auto) child_width += child.dimensions.margin.right;
            if (should_sum) {
                sum_width += child_width;
            } else {
                max_width = @max(max_width, child_width);
            }
        } else {
            // Auto-width child — recurse to find its intrinsic content width,
            // then add its padding/border (but not auto margins).
            const inner_width = measureIntrinsicWidth(child);
            const h_extras = child.dimensions.padding.left + child.dimensions.padding.right +
                child.dimensions.border.left + child.dimensions.border.right;
            var child_width = inner_width + h_extras;

            // Apply min-width constraint: auto-width block children with
            // min-width must respect it during intrinsic sizing.
            if (c_style) |cs| {
                if (cs.min_width) |mw| {
                    const min_w: f32 = switch (mw.unit) {
                        .px => mw.value,
                        .em => mw.value * cs.font_size.value,
                        else => 0,
                    };
                    if (min_w > 0) {
                        if (cs.box_sizing == .border_box) {
                            // min-width is the border-box total — compare directly
                            child_width = @max(child_width, min_w);
                        } else {
                            // min-width is content-box — add padding+border for comparison
                            child_width = @max(child_width, min_w + h_extras);
                        }
                    }
                }
            }

            if (child_width > 0) {
                const ml_auto = if (c_style) |cs| cs.margin_left.unit == .auto else false;
                const mr_auto = if (c_style) |cs| cs.margin_right.unit == .auto else false;
                if (!ml_auto) child_width += child.dimensions.margin.left;
                if (!mr_auto) child_width += child.dimensions.margin.right;
                if (should_sum) {
                    sum_width += child_width;
                } else {
                    max_width = @max(max_width, child_width);
                }
            }
        }
    }

    if (should_sum) {
        return @max(max_width, sum_width);
    }
    return max_width;
}

const FlexLine = struct {
    start: usize,
    end: usize,
    main_size: f32,
    cross_size: f32,
};

/// Resolve a definite containing-block height for percentage height resolution.
/// Returns 0 when the containing block has no explicit height (indefinite).
fn resolveDefiniteHeight(cb: *LayoutBox, ctx: layout.LayoutContext) f32 {
    if (cb.styled_node) |cb_sn| {
        // Initial containing block: document node uses viewport height.
        if (cb_sn.node.node_type == .document) {
            return ctx.viewport_height;
        }
        if (cb_sn.style.height) |h| {
            switch (h.unit) {
                .percent => {
                    const gp_h = if (cb.parent) |gp|
                        resolveDefiniteHeight(gp, ctx)
                    else
                        ctx.viewport_height;
                    // Fix: if parent has forced height but h is auto, resolve against it
                    const parent_h = if (gp_h == 0) ctx.forced_cross_size else gp_h;
                    if (parent_h == 0) return 0;
                    const resolved = (h.value / 100.0) * parent_h;
                    if (cb_sn.style.box_sizing == .border_box) {
                        const v_extras = cb.dimensions.padding.top + cb.dimensions.padding.bottom +
                            cb.dimensions.border.top + cb.dimensions.border.bottom;
                        return @max(0, resolved - v_extras);
                    }
                    return resolved;
                },
                .px, .em, .rem, .vh, .vw, .calc => {
                    const resolved = layout.resolveLength(h, ctx.viewport_height, ctx, cb_sn.style.font_size.value);
                    if (cb_sn.style.box_sizing == .border_box) {
                        const v_extras = cb.dimensions.padding.top + cb.dimensions.padding.bottom +
                            cb.dimensions.border.top + cb.dimensions.border.bottom;
                        return @max(0, resolved - v_extras);
                    }
                    return resolved;
                },
                .auto, .none => return ctx.forced_cross_size,
            }
        } else if (cb.dimensions.content.height > 0) {
            // If we have a visible height already (from a previous pass or fixed size), use it.
            return cb.dimensions.content.height;
        } else {
            return ctx.forced_cross_size;
        }
    }
    return 0;
}

/// Resolve a flex container's height with proper percent handling.
/// Returns null when the height is indefinite (percent against auto CB).
fn resolveFlexHeight(height: ?values.Length, containing_block: ?*LayoutBox, ctx: layout.LayoutContext, font_size: f32) ?f32 {
    const h = height orelse return null;
    const cb_height = if (containing_block) |cb| resolveDefiniteHeight(cb, ctx) else ctx.viewport_height;
    if ((h.unit == .percent or h.unit == .calc) and cb_height == 0) return null;
    return layout.resolveLength(h, cb_height, ctx, font_size);
}

fn moveSubtreeTo(child: *LayoutBox, target_x: f32, target_y: f32) void {
    const dx = target_x - child.dimensions.content.x;
    const dy = target_y - child.dimensions.content.y;
    if (dx != 0) block_metrics.shiftBoxX(child, dx);
    if (dy != 0) block_metrics.shiftBoxY(child, dy);
}

/// RC-31: After moveSubtreeTo shifts a subtree, re-apply absolute/fixed positioning
/// for any descendants that were already positioned by applyPositioning.
/// These children's coordinates were set to absolute values and got corrupted
/// by the recursive shift.
fn reapplyAbsolutePositioning(node: *LayoutBox, ctx: layout.LayoutContext) void {
    for (node.children.items) |child| {
        if (child.styled_node) |sn| {
            if (sn.style.position == .absolute or sn.style.position == .fixed) {
                position.applyPositioning(child, ctx);
                // Don't recurse into abs-pos subtrees — they have their own
                // coordinate system relative to their containing block
                continue;
            }
        }
        reapplyAbsolutePositioning(child, ctx);
    }
}

/// RC-43: After a parent stretches a flex child's cross-axis, propagate that
/// stretch to the child's own children (grandchildren). This avoids a full
/// re-layout which would recompute widths/positions and cause regressions.
/// Only applies to flex containers whose cross-axis was set by stretch (not
/// by an explicit height/width).
fn propagateCrossStretch(node: *LayoutBox) void {
    const style = if (node.styled_node) |sn| &sn.style else return;
    const node_is_row = style.flex_direction == .row;

    // The cross-axis size of this node is what its children should stretch to
    const cross_size = if (node_is_row) node.dimensions.content.height else node.dimensions.content.width;
    if (cross_size <= 0) return;

    for (node.children.items) |child| {
        const c_style = if (child.styled_node) |sn| &sn.style else continue;

        // Skip out-of-flow children
        if (c_style.position == .absolute or c_style.position == .fixed) continue;

        // Determine effective alignment
        const effective_align = c_style.align_self orelse style.align_items;
        if (effective_align != .stretch) continue;

        // Check if child has explicit cross-axis size
        const has_explicit_cross = if (node_is_row) c_style.height != null else c_style.width != null;
        if (has_explicit_cross) continue;

        // Compute stretched size for this child
        const child_cross_extras = if (node_is_row)
            child.dimensions.margin.top + child.dimensions.margin.bottom +
                child.dimensions.border.top + child.dimensions.border.bottom +
                child.dimensions.padding.top + child.dimensions.padding.bottom
        else
            child.dimensions.margin.left + child.dimensions.margin.right +
                child.dimensions.border.left + child.dimensions.border.right +
                child.dimensions.padding.left + child.dimensions.padding.right;
        const stretched = @max(0, cross_size - child_cross_extras);
        if (node_is_row) {
            child.dimensions.content.height = stretched;
        } else {
            child.dimensions.content.width = stretched;
        }

        // Recurse into flex container children
        if (stretched > 0 and child.box_type == .flexNode) {
            propagateCrossStretch(child);
        }
    }
}

pub fn layoutFlexBox(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    const style = if (box.styled_node) |sn| &sn.style else return;

    // Don't propagate forced_cross_size to children's contexts — it only
    // applies to THIS box's container_cross_size computation.
    var local_ctx = ctx;
    local_ctx.forced_cross_size = 0;

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

    // Subtract container's own padding/border from content width when appropriate
    const has_explicit_w = style.width != null;
    const h_extras = box.dimensions.padding.left + box.dimensions.padding.right + box.dimensions.border.left + box.dimensions.border.right;

    if (style.box_sizing == .border_box or !has_explicit_w) {
        // border-box: width includes padding/border, subtract them
        // auto-width (no explicit width): cb_width is available space, subtract own padding/border
        box.dimensions.content.width = @max(0, specified_w - h_extras);
    } else {
        // content-box with explicit width: width IS the content width
        box.dimensions.content.width = specified_w;
    }

    // Apply min-width constraint
    if (style.min_width) |mw| {
        const min_w = layout.resolveLength(mw, cb_width, ctx, style.font_size.value);
        if (style.box_sizing == .border_box) {
            box.dimensions.content.width = @max(box.dimensions.content.width, @max(0, min_w - h_extras));
        } else {
            box.dimensions.content.width = @max(box.dimensions.content.width, min_w);
        }
    }

    // Apply max-width constraint
    if (style.max_width) |mw| {
        const max_w = layout.resolveLength(mw, cb_width, ctx, style.font_size.value);
        if (style.box_sizing == .border_box) {
            box.dimensions.content.width = @min(box.dimensions.content.width, @max(0, max_w - h_extras));
        } else {
            box.dimensions.content.width = @min(box.dimensions.content.width, max_w);
        }
    }

    // Per CSS 2.1 §10.3.3: auto margins absorb remaining space when used width < CB width.
    const width_is_auto = style.width == null;
    const available_space_h = cb_width - (box.dimensions.margin.left + box.dimensions.margin.right + h_extras);
    const was_clamped_narrower = width_is_auto and (box.dimensions.content.width < available_space_h) and (box.dimensions.content.width > 0);

    if (!width_is_auto or was_clamped_narrower) {
        const used_width = box.dimensions.margin.left + box.dimensions.border.left + box.dimensions.padding.left + box.dimensions.content.width + box.dimensions.padding.right + box.dimensions.border.right + box.dimensions.margin.right;
        const remaining = cb_width - used_width;
        if (remaining > 0) {
            const ml_auto = style.margin_left.unit == .auto;
            const mr_auto = style.margin_right.unit == .auto;
            if (ml_auto and mr_auto) {
                box.dimensions.margin.left += remaining / 2.0;
                box.dimensions.margin.right += remaining / 2.0;
            } else if (ml_auto) {
                box.dimensions.margin.left += remaining;
            } else if (mr_auto) {
                box.dimensions.margin.right += remaining;
            }
        }
    }

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
    const resolved_height = resolveFlexHeight(style.height, containing_block, ctx, style.font_size.value);
    const container_main_size = if (is_row)
        box.dimensions.content.width
    else if (resolved_height) |rh|
        rh
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
            if (fb.unit == .auto) {
                // flex-basis: auto → use the item's main size property (width/height)
                if (is_row) {
                    if (c_style.width) |w| base_size = layout.resolveLength(w, box.dimensions.content.width, ctx, c_style.font_size.value);
                } else {
                    if (c_style.height) |h| base_size = layout.resolveLength(h, container_main_size, ctx, c_style.font_size.value);
                }
            } else {
                base_size = layout.resolveLength(fb, if (is_row) box.dimensions.content.width else container_main_size, ctx, c_style.font_size.value);
            }
        } else if (is_row) {
            if (c_style.width) |w| base_size = layout.resolveLength(w, box.dimensions.content.width, ctx, c_style.font_size.value);
        } else {
            if (c_style.height) |h| base_size = layout.resolveLength(h, container_main_size, ctx, c_style.font_size.value);
        }

        const c_h_extras = child.dimensions.padding.left + child.dimensions.padding.right + child.dimensions.border.left + child.dimensions.border.right;
        const c_v_extras = child.dimensions.padding.top + child.dimensions.padding.bottom + child.dimensions.border.top + child.dimensions.border.bottom;

        base_sizes[i] = base_size;

        if (is_row) {
            // Only set explicit width if item has a definite main-axis size.
            // Items with no flex-basis and no width (base_size == 0) should
            // be left unset so block layout computes their content-based size
            // (CSS Flexbox §9.2: auto flex-basis + auto width → max-content).
            if (base_size > 0 or c_style.flex_basis != null or c_style.width != null) {
                if (c_style.box_sizing == .border_box) {
                    child.dimensions.content.width = @max(0, base_size - c_h_extras);
                } else {
                    child.dimensions.content.width = base_size;
                }
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

    const has_definite_main = is_row or resolved_height != null;
    var available_space = container_main_size - total_base_size;

    if (available_space > 0 and total_grow > 0 and !wraps_main_axis) {
        for (children.items) |child| {
            const c_style = if (child.styled_node) |sn| &sn.style else continue;
            const extra = (c_style.flex_grow / total_grow) * available_space;
            if (is_row) {
                child.dimensions.content.width += extra;
                // Only lock items that actually received grow space (flex_grow > 0).
                // Items with flex_grow=0 get extra=0 and must remain unlocked so
                // Pass 2b can compute their content-based shrink-to-fit width.
                if (c_style.flex_grow > 0) {
                    child.lock_content_width = true;
                }
            } else {
                child.dimensions.content.height += extra;
                if (c_style.flex_grow > 0) {
                    child.lock_content_height = true;
                }
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
    // Only lock items that have an explicit main-axis size (flex-basis or width/height).
    // Items with auto main size should remain unlocked so block layout can
    // compute their content-based intrinsic width (CSS Flexbox §9.2).
    for (children.items, 0..) |child, i| {
        if (is_row) {
            if (base_sizes[i] > 0 or child.lock_content_width) {
                child.lock_content_width = true;
            }
        } else {
            if (base_sizes[i] > 0 or child.lock_content_height) {
                child.lock_content_height = true;
            }
        }
    }

    // Pass 2: Layout each child fully
    for (children.items) |child| {
        // Each flex item establishes a new BFC (CSS Flexbox §3)
        var item_fc = layout.FloatContext.init(ctx.allocator);
        defer item_fc.deinit();
        var item_ctx = local_ctx;
        item_ctx.float_ctx = &item_fc;

        if (child.box_type == .flexNode) {
            layoutFlexBox(child, box, item_ctx);
        } else {
            child.is_bfc = true;
            block.layoutBlock(child, box, item_ctx);
        }
    }

    // Column flex re-adjustment: after Pass 2, auto-height items have their
    // actual content heights. Recalculate available space and redistribute
    // flex-grow space based on actual sizes (column equivalent of RC-29/RC-40).
    if (!is_row and container_main_size > 0 and total_grow > 0) {
        var actual_total: f32 = 0;
        for (children.items, 0..) |child, ci| {
            const c_style = if (child.styled_node) |sn| &sn.style else continue;
            const margin_main = child.dimensions.margin.top + child.dimensions.margin.bottom;
            const c_v_extras = child.dimensions.padding.top + child.dimensions.padding.bottom +
                child.dimensions.border.top + child.dimensions.border.bottom;

            if (c_style.flex_grow > 0 and child.lock_content_height) {
                // For grow items, use their base_size (not their inflated size)
                if (c_style.box_sizing == .border_box) {
                    actual_total += base_sizes[ci] + margin_main;
                } else {
                    actual_total += base_sizes[ci] + c_v_extras + margin_main;
                }
            } else {
                // For non-grow items, use their actual laid-out height
                actual_total += child.dimensions.marginBox().height;
            }
            if (ci + 1 < children.items.len) actual_total += main_gap;
        }

        const real_available = container_main_size - actual_total;

        if (real_available > 0) {
            // Redistribute grow space with correct available
            for (children.items, 0..) |child, ci| {
                const c_style = if (child.styled_node) |sn| &sn.style else continue;
                if (c_style.flex_grow > 0 and child.lock_content_height) {
                    const c_v_extras = child.dimensions.padding.top + child.dimensions.padding.bottom +
                        child.dimensions.border.top + child.dimensions.border.bottom;
                    const content_base = if (c_style.box_sizing == .border_box)
                        @max(0, base_sizes[ci] - c_v_extras)
                    else
                        base_sizes[ci];
                    const extra = (c_style.flex_grow / total_grow) * real_available;
                    child.dimensions.content.height = content_base + extra;

                    // Re-layout with corrected height
                    var item_fc = layout.FloatContext.init(ctx.allocator);
                    defer item_fc.deinit();
                    var item_ctx = local_ctx;
                    item_ctx.float_ctx = &item_fc;
                    if (child.box_type == .flexNode) {
                        const saved_h = child.dimensions.content.height;
                        layoutFlexBox(child, box, item_ctx);
                        child.dimensions.content.height = saved_h;
                    } else {
                        child.is_bfc = true;
                        child.lock_content_height = true;
                        block.layoutBlock(child, box, item_ctx);
                    }
                }
            }
        } else {
            // No space left — reset grow items to their base content height
            for (children.items, 0..) |child, ci| {
                const c_style = if (child.styled_node) |sn| &sn.style else continue;
                if (c_style.flex_grow > 0 and child.lock_content_height) {
                    const c_v_extras = child.dimensions.padding.top + child.dimensions.padding.bottom +
                        child.dimensions.border.top + child.dimensions.border.bottom;
                    const content_base = if (c_style.box_sizing == .border_box)
                        @max(0, base_sizes[ci] - c_v_extras)
                    else
                        base_sizes[ci];
                    child.dimensions.content.height = content_base;
                    child.lock_content_height = true;

                    var item_fc = layout.FloatContext.init(ctx.allocator);
                    defer item_fc.deinit();
                    var item_ctx = local_ctx;
                    item_ctx.float_ctx = &item_fc;
                    if (child.box_type == .flexNode) {
                        layoutFlexBox(child, box, item_ctx);
                        child.dimensions.content.height = content_base;
                    } else {
                        child.is_bfc = true;
                        block.layoutBlock(child, box, item_ctx);
                    }
                }
            }
        }
    }

    // Pass 2b: For auto-width row flex items, shrink-to-fit their content width.
    // Block layout (calculateWidth) gives auto-width blocks the full containing-block
    // width. But per CSS Flexbox §9.2, flex items with auto flex-basis and auto width
    // should use their max-content size (shrink-to-fit), not fill the container.
    if (is_row) {
        var needs_recalc = false;
        for (children.items, 0..) |child, i| {
            // Identify auto-width items: base_size was 0 (no flex-basis, no explicit width)
            // and the item was not given grow/shrink space (lock_content_width still false).
            if (base_sizes[i] == 0 and !child.lock_content_width) {
                const content_origin_x = child.dimensions.content.x;
                const max_content_right = measureMaxContentRight(child, content_origin_x);

                if (max_content_right > 0) {
                    child.dimensions.content.width = max_content_right;
                    // RC-60: For border-box items, base_sizes must store the border-box width
                    // (content + padding + border), not just content width. The recalc loop
                    // at line ~574 assumes border-box items already include padding+border.
                    const c_stl = if (child.styled_node) |sn| &sn.style else null;
                    if (c_stl != null and c_stl.?.box_sizing == .border_box) {
                        base_sizes[i] = max_content_right + child.dimensions.padding.left + child.dimensions.padding.right + child.dimensions.border.left + child.dimensions.border.right;
                    } else {
                        base_sizes[i] = max_content_right;
                    }
                    needs_recalc = true;

                    // RC-39: Re-layout flex items after shrink-to-fit so their
                    // children are sized correctly for the new, smaller width.
                    // Pass `child` as its own containing block so layoutFlexBox
                    // derives cb_width from the shrunk content width, not from
                    // the parent's (much wider) container.
                    if (child.box_type == .flexNode) {
                        const shrunk_width = max_content_right;
                        var item_fc = layout.FloatContext.init(ctx.allocator);
                        defer item_fc.deinit();
                        var item_ctx = local_ctx;
                        item_ctx.float_ctx = &item_fc;
                        layoutFlexBox(child, child, item_ctx);
                        // Restore the shrunk width (layoutFlexBox may overwrite it)
                        child.dimensions.content.width = shrunk_width;
                    }
                }
            }
        }

        // Recalculate total_base_size and available_space for correct Pass 3 positioning
        if (needs_recalc) {
            total_base_size = 0;
            for (children.items, 0..) |_, ci| {
                const child = children.items[ci];
                const c_style = if (child.styled_node) |sn| &sn.style else continue;
                const margin_main = child.dimensions.margin.left + child.dimensions.margin.right;
                const c_h_extras = child.dimensions.padding.left + child.dimensions.padding.right + child.dimensions.border.left + child.dimensions.border.right;
                if (c_style.box_sizing == .border_box) {
                    total_base_size += base_sizes[ci] + margin_main;
                } else {
                    total_base_size += base_sizes[ci] + c_h_extras + margin_main;
                }
            }
            if (children.items.len > 1) {
                total_base_size += main_gap * @as(f32, @floatFromInt(children.items.len - 1));
            }
            available_space = container_main_size - total_base_size;

            // RC-40: When available space is zero or negative after recalculation,
            // flex-grow items that were inflated in the initial grow pass
            // must be reset to their base content width (no grow space left).
            if (total_grow > 0 and available_space <= 0) {
                for (children.items, 0..) |child, ci| {
                    const c_style = if (child.styled_node) |sn| &sn.style else continue;
                    if (c_style.flex_grow > 0 and child.lock_content_width) {
                        const c_h_extras = child.dimensions.padding.left + child.dimensions.padding.right +
                            child.dimensions.border.left + child.dimensions.border.right;
                        const content_base = if (c_style.box_sizing == .border_box)
                            @max(0, base_sizes[ci] - c_h_extras)
                        else
                            base_sizes[ci];
                        child.dimensions.content.width = content_base;

                        // Re-layout with corrected (deflated) width
                        var item_fc = layout.FloatContext.init(ctx.allocator);
                        defer item_fc.deinit();
                        var item_ctx = local_ctx;
                        item_ctx.float_ctx = &item_fc;
                        if (child.box_type == .flexNode) {
                            layoutFlexBox(child, child, item_ctx);
                        } else {
                            child.is_bfc = true;
                            block.layoutBlock(child, box, item_ctx);
                        }
                        child.dimensions.content.width = content_base;
                    }
                }
                available_space = 0;
            }

            // RC-29: Re-adjust flex-grow items now that auto-width sizes are known.
            // The initial grow pass used total_base_size that excluded auto-width
            // items' actual content sizes. Now that Pass 2b measured them, the
            // available space for grow items has changed.
            if (total_grow > 0 and available_space > 0) {
                for (children.items, 0..) |child, ci| {
                    const c_style = if (child.styled_node) |sn| &sn.style else continue;
                    if (c_style.flex_grow > 0 and child.lock_content_width) {
                        const c_h_extras = child.dimensions.padding.left + child.dimensions.padding.right +
                            child.dimensions.border.left + child.dimensions.border.right;
                        const content_base = if (c_style.box_sizing == .border_box)
                            @max(0, base_sizes[ci] - c_h_extras)
                        else
                            base_sizes[ci];
                        const extra = (c_style.flex_grow / total_grow) * available_space;
                        const corrected_width = content_base + extra;
                        child.dimensions.content.width = corrected_width;

                        // RC-44: Re-layout with corrected width. Pass `child`
                        // as its own containing block so that layoutFlexBox
                        // derives cb_width from the child's pre-set content
                        // width (corrected_width), not from the parent's wider
                        // container. This ensures the child's descendants see
                        // the correct flex-grow-allocated width.
                        var item_fc = layout.FloatContext.init(ctx.allocator);
                        defer item_fc.deinit();
                        var item_ctx = local_ctx;
                        item_ctx.float_ctx = &item_fc;
                        if (child.box_type == .flexNode) {
                            layoutFlexBox(child, child, item_ctx);
                        } else {
                            child.is_bfc = true;
                            block.layoutBlock(child, box, item_ctx);
                        }
                        child.dimensions.content.width = corrected_width;
                    }
                }
                available_space = 0;
            }
        }
    }

    // Pass 2c: For column flex with align-items != stretch, shrink children's
    // cross-axis (width) to their content extent. Block layout gives auto-width
    // blocks the full containing-block width, but per CSS Flexbox spec, non-stretch
    // items should use their content-based (shrink-to-fit) width.
    if (!is_row and style.align_items != .stretch) {
        for (children.items) |child| {
            const c_style = if (child.styled_node) |sn| &sn.style else continue;
            const has_explicit_width = c_style.width != null and c_style.width.?.unit != .auto;
            if (!has_explicit_width) {
                const content_origin_x = child.dimensions.content.x;
                const max_content_right = measureMaxContentRight(child, content_origin_x);
                if (max_content_right > 0 and max_content_right < child.dimensions.content.width) {
                    child.dimensions.content.width = max_content_right;
                }
            }
        }
    }

    // Pass 2d: Handle auto margins on the main axis.
    // Per CSS Flexbox §8.1, auto margins on flex items absorb free space on the
    // main axis before justify-content is applied.
    if (has_definite_main and container_main_size > 0) {
        var total_main: f32 = 0;
        for (children.items, 0..) |child, i| {
            if (is_row) {
                total_main += child.dimensions.marginBox().width;
            } else {
                total_main += child.dimensions.marginBox().height;
            }
            if (i + 1 < children.items.len) total_main += main_gap;
        }
        const free_space = container_main_size - total_main;
        if (free_space > 0) {
            var auto_margin_count: f32 = 0;
            for (children.items) |child| {
                const cs = if (child.styled_node) |sn| &sn.style else continue;
                if (is_row) {
                    if (cs.margin_left.unit == .auto) auto_margin_count += 1;
                    if (cs.margin_right.unit == .auto) auto_margin_count += 1;
                } else {
                    if (cs.margin_top.unit == .auto) auto_margin_count += 1;
                    if (cs.margin_bottom.unit == .auto) auto_margin_count += 1;
                }
            }
            if (auto_margin_count > 0) {
                const per_auto = free_space / auto_margin_count;
                for (children.items) |child| {
                    const cs = if (child.styled_node) |sn| &sn.style else continue;
                    if (is_row) {
                        if (cs.margin_left.unit == .auto) child.dimensions.margin.left = per_auto;
                        if (cs.margin_right.unit == .auto) child.dimensions.margin.right = per_auto;
                    } else {
                        if (cs.margin_top.unit == .auto) child.dimensions.margin.top = per_auto;
                        if (cs.margin_bottom.unit == .auto) child.dimensions.margin.bottom = per_auto;
                    }
                }
                // Free space is now absorbed by margins, so justify-content sees 0.
                available_space = 0;
            }
        }
    }

    // Pass 3: Position children and resolve cross-axis alignment
    var max_cross_size: f32 = 0;
    const container_cross_size = if (is_row) blk: {
        if (style.height) |h| {
            var cs = layout.resolveLength(h, ctx.viewport_height, ctx, style.font_size.value);
            if (style.box_sizing == .border_box) {
                const v_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                    box.dimensions.border.top + box.dimensions.border.bottom;
                cs = @max(0, cs - v_extras);
            }
            break :blk cs;
        } else {
            // Use forced_cross_size if parent stretched us, otherwise 0
            break :blk ctx.forced_cross_size;
        }
    } else box.dimensions.content.width;

    if (wraps_main_axis) {
        // Normalize single-line items that have an inflated content height by
        // snapping them back to their single anonymous-block child's height.
        for (children.items) |child| {
            const c_style = if (child.styled_node) |sn| &sn.style else continue;
            if (c_style.height != null) continue;
            if (child.children.items.len == 1 and child.children.items[0].box_type == .anonymousBlock) {
                const natural = child.children.items[0].dimensions.content.height;
                if (natural > 0) {
                    child.dimensions.content.height = natural;
                }
            }
        }

        var lines = std.ArrayListUnmanaged(FlexLine){};
        defer lines.deinit(ctx.allocator);

        var line_start: usize = 0;
        var line_main: f32 = 0;
        var line_cross: f32 = 0;

        for (children.items, 0..) |child, i| {
            const child_main = child.dimensions.marginBox().width;
            const child_cross = blk: {
                if (child.children.items.len == 1 and child.children.items[0].box_type == .anonymousBlock) {
                    const natural = child.children.items[0].dimensions.content.height;
                    const extras = child.dimensions.margin.top + child.dimensions.margin.bottom +
                        child.dimensions.border.top + child.dimensions.border.bottom +
                        child.dimensions.padding.top + child.dimensions.padding.bottom;
                    break :blk natural + extras;
                }
                break :blk child.dimensions.marginBox().height;
            };
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
                    .space_around => {
                        const line_count = line.end - line.start;
                        if (line_count > 0) {
                            line_spacing = line_available / @as(f32, @floatFromInt(line_count));
                            line_main_pos = line_spacing / 2.0;
                        }
                    },
                    .space_evenly => {
                        const line_count = line.end - line.start;
                        if (line_count > 0) {
                            line_spacing = line_available / @as(f32, @floatFromInt(line_count + 1));
                            line_main_pos = line_spacing;
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
                reapplyAbsolutePositioning(child, ctx);

                const child_full_cross_size = child.dimensions.marginBox().height;
                // Determine effective alignment for this child (align-self overrides align-items)
                const c_align_style = if (child.styled_node) |sn| &sn.style else null;
                const effective_align = if (c_align_style) |cs| (cs.align_self orelse style.align_items) else style.align_items;

                // L-7 FIX: Implement stretch for wrapping flex too
                if (effective_align == .stretch) {
                    const has_explicit_height = if (c_align_style) |cs| cs.height != null else false;
                    if (!has_explicit_height) {
                        const child_cross_extras = child.dimensions.margin.top + child.dimensions.margin.bottom +
                            child.dimensions.border.top + child.dimensions.border.bottom +
                            child.dimensions.padding.top + child.dimensions.padding.bottom;
                        const stretched_size = @max(0, line.cross_size - child_cross_extras);
                        child.dimensions.content.height = stretched_size;

                        // RC-43: Propagate stretch to nested flex children (wrapping path)
                        if (stretched_size > 0 and child.box_type == .flexNode) {
                            propagateCrossStretch(child);
                        }
                    }
                }
                const cross_offset = switch (effective_align) {
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

        // Post-pass: clamp single-line anonymous-block items back to their
        // natural content height (avoid inflated stretch artifacts).
        for (children.items) |child| {
            if (child.children.items.len == 1 and child.children.items[0].box_type == .anonymousBlock) {
                const natural = child.children.items[0].dimensions.content.height;
                if (natural > 0) {
                    child.dimensions.content.height = natural;
                }
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
                .space_around => {
                    if (children.items.len > 0) {
                        spacing = available_space / @as(f32, @floatFromInt(children.items.len));
                        main_pos = spacing / 2.0;
                    }
                },
                .space_evenly => {
                    if (children.items.len > 0) {
                        spacing = available_space / @as(f32, @floatFromInt(children.items.len + 1));
                        main_pos = spacing;
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
                reapplyAbsolutePositioning(child, ctx);
            } else {
                const target_y = box.dimensions.content.y + main_pos + child.dimensions.margin.top + child.dimensions.border.top + child.dimensions.padding.top;
                const target_x = box.dimensions.content.x + child.dimensions.margin.left + child.dimensions.border.left + child.dimensions.padding.left;
                moveSubtreeTo(child, target_x, target_y);
                reapplyAbsolutePositioning(child, ctx);
            }

            // Normalize zero-height items that have visible children (RC-54 FIX)
            if (child.dimensions.content.height == 0 and child.children.items.len > 0) {
                var max_y: f32 = 0;
                for (child.children.items) |c| {
                    max_y = @max(max_y, c.dimensions.marginBox().height);
                }
                if (max_y > 0) {
                    child.dimensions.content.height = max_y;
                }
            }

            // Apply align-items cross-axis offset
            const child_full_cross_size = if (is_row) child.dimensions.marginBox().height else child.dimensions.marginBox().width;
            if (container_cross_size > 0) {
                // Determine effective alignment for this child (align-self overrides align-items)
                const c_align_style = if (child.styled_node) |sn| &sn.style else null;
                const effective_align = if (c_align_style) |cs| (cs.align_self orelse style.align_items) else style.align_items;

                // L-7 FIX: Implement actual stretch behavior for align-items: stretch
                if (effective_align == .stretch) {
                    const has_explicit_cross = if (c_align_style) |cs| (if (is_row) cs.height != null else cs.width != null) else false;
                    if (!has_explicit_cross) {
                        // Stretch child's cross-axis content size to fill container
                        const child_cross_extras = if (is_row)
                            child.dimensions.margin.top + child.dimensions.margin.bottom +
                                child.dimensions.border.top + child.dimensions.border.bottom +
                                child.dimensions.padding.top + child.dimensions.padding.bottom
                        else
                            child.dimensions.margin.left + child.dimensions.margin.right +
                                child.dimensions.border.left + child.dimensions.border.right +
                                child.dimensions.padding.left + child.dimensions.padding.right;
                        const stretched_size = @max(0, container_cross_size - child_cross_extras);
                        if (is_row) {
                            child.dimensions.content.height = stretched_size;
                        } else {
                            child.dimensions.content.width = stretched_size;
                        }

                        // RC-43: Propagate stretch to nested flex children.
                        // Instead of re-laying-out (which recomputes widths and
                        // positions, causing regressions), just recursively
                        // set cross-axis sizes on stretch-aligned descendants.
                        if (stretched_size > 0 and child.box_type == .flexNode) {
                            propagateCrossStretch(child);
                        }
                    }
                }

                const cross_offset = switch (effective_align) {
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

        if (!is_row and resolved_height == null) {
            max_cross_size = main_pos;
        }
    }

    if (resolved_height == null) {
        box.dimensions.content.height = max_cross_size;
    } else {
        var resolved_h = resolved_height.?;
        if (style.box_sizing == .border_box) {
            const v_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                box.dimensions.border.top + box.dimensions.border.bottom;
            resolved_h = @max(0, resolved_h - v_extras);
        }
        box.dimensions.content.height = resolved_h;
    }

    // Apply min-height constraint
    if (style.min_height) |mh| {
        const min_h = layout.resolveLength(mh, ctx.viewport_height, ctx, style.font_size.value);
        if (style.box_sizing == .border_box) {
            const v_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                box.dimensions.border.top + box.dimensions.border.bottom;
            box.dimensions.content.height = @max(box.dimensions.content.height, @max(0, min_h - v_extras));
        } else {
            box.dimensions.content.height = @max(box.dimensions.content.height, min_h);
        }
    }

    // RC-43: Post-min-height stretch pass.
    // When a row flex container has no explicit height but min-height increased
    // the content height beyond what was used in Pass 3 (container_cross_size was 0),
    // children that should have been stretched were skipped. Stretch them now
    // using the final content height.
    if (is_row and style.height == null and box.dimensions.content.height > 0 and container_cross_size <= 0) {
        const final_cross = box.dimensions.content.height;
        for (children.items) |child| {
            const c_style = if (child.styled_node) |sn| &sn.style else continue;
            if (c_style.position == .absolute or c_style.position == .fixed) continue;

            const effective_align = c_style.align_self orelse style.align_items;
            if (effective_align != .stretch) continue;

            const has_explicit_cross = c_style.height != null;
            if (has_explicit_cross) continue;

            const child_cross_extras =
                child.dimensions.margin.top + child.dimensions.margin.bottom +
                child.dimensions.border.top + child.dimensions.border.bottom +
                child.dimensions.padding.top + child.dimensions.padding.bottom;
            const stretched_size = @max(0, final_cross - child_cross_extras);
            child.dimensions.content.height = stretched_size;

            // Propagate stretch into nested flex containers
            if (stretched_size > 0 and child.box_type == .flexNode) {
                propagateCrossStretch(child);
            }
        }
    }

    // Apply max-height constraint
    if (style.max_height) |mh| {
        const max_h = layout.resolveLength(mh, ctx.viewport_height, ctx, style.font_size.value);
        if (style.box_sizing == .border_box) {
            const v_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                box.dimensions.border.top + box.dimensions.border.bottom;
            box.dimensions.content.height = @min(box.dimensions.content.height, @max(0, max_h - v_extras));
        } else {
            box.dimensions.content.height = @min(box.dimensions.content.height, max_h);
        }
    }
}

// ── Tests ───────────────────────────────────────────────────────────────

const dom = @import("../dom/mod.zig");
const resolver = @import("../css/resolver.zig");
const properties = @import("../css/properties.zig");

test "RC-37: measureIntrinsicWidth sums children for row flex containers" {
    const allocator = std.testing.allocator;

    // Create two child DOM nodes
    var child_node1 = dom.Node.init(allocator, .element);
    var child_node2 = dom.Node.init(allocator, .element);

    // Styled nodes with explicit widths (24px content width)
    var child_sn1 = resolver.StyledNode{
        .node = &child_node1,
        .style = properties.ComputedStyle{
            .width = .{ .value = 24, .unit = .px },
        },
        .children = &.{},
    };
    var child_sn2 = resolver.StyledNode{
        .node = &child_node2,
        .style = properties.ComputedStyle{
            .width = .{ .value = 24, .unit = .px },
        },
        .children = &.{},
    };

    // Create child LayoutBoxes: 24px content + 8px padding each side = 40px total
    var child1 = LayoutBox.init(.blockNode, &child_sn1);
    child1.dimensions.content.width = 24;
    child1.dimensions.padding.left = 8;
    child1.dimensions.padding.right = 8;

    var child2 = LayoutBox.init(.blockNode, &child_sn2);
    child2.dimensions.content.width = 24;
    child2.dimensions.padding.left = 8;
    child2.dimensions.padding.right = 8;

    // Create the row flex parent
    var parent_node = dom.Node.init(allocator, .element);
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = properties.ComputedStyle{
            .display = .flex,
            .flex_direction = .row,
        },
        .children = &.{},
    };
    var parent = LayoutBox.init(.flexNode, &parent_sn);

    // Add children to parent
    parent.children.append(allocator, &child1) catch unreachable;
    parent.children.append(allocator, &child2) catch unreachable;
    defer parent.children.deinit(allocator);

    // Row flex: intrinsic width should be SUM = 40 + 40 = 80, not MAX = 40
    const width = measureIntrinsicWidth(&parent);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), width, 0.01);
}

test "RC-37: measureIntrinsicWidth takes max for column flex containers" {
    const allocator = std.testing.allocator;

    var child_node1 = dom.Node.init(allocator, .element);
    var child_node2 = dom.Node.init(allocator, .element);

    var child_sn1 = resolver.StyledNode{
        .node = &child_node1,
        .style = properties.ComputedStyle{
            .width = .{ .value = 24, .unit = .px },
        },
        .children = &.{},
    };
    var child_sn2 = resolver.StyledNode{
        .node = &child_node2,
        .style = properties.ComputedStyle{
            .width = .{ .value = 24, .unit = .px },
        },
        .children = &.{},
    };

    var child1 = LayoutBox.init(.blockNode, &child_sn1);
    child1.dimensions.content.width = 24;
    child1.dimensions.padding.left = 8;
    child1.dimensions.padding.right = 8;

    var child2 = LayoutBox.init(.blockNode, &child_sn2);
    child2.dimensions.content.width = 24;
    child2.dimensions.padding.left = 8;
    child2.dimensions.padding.right = 8;

    var parent_node = dom.Node.init(allocator, .element);
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = properties.ComputedStyle{
            .display = .flex,
            .flex_direction = .column,
        },
        .children = &.{},
    };
    var parent = LayoutBox.init(.flexNode, &parent_sn);

    parent.children.append(allocator, &child1) catch unreachable;
    parent.children.append(allocator, &child2) catch unreachable;
    defer parent.children.deinit(allocator);

    // Column flex: intrinsic width should be MAX = 40, not SUM = 80
    const width = measureIntrinsicWidth(&parent);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), width, 0.01);
}

test "RC-38: layoutFlexBox content-box width not reduced by padding" {
    const allocator = std.testing.allocator;

    // Create a containing block with 200px content width
    var cb_node = dom.Node.init(allocator, .element);
    var cb_sn = resolver.StyledNode{
        .node = &cb_node,
        .style = properties.ComputedStyle{
            .display = .block,
        },
        .children = &.{},
    };
    var cb = LayoutBox.init(.blockNode, &cb_sn);
    cb.dimensions.content.width = 200;

    // Create the flex container: width=24px, padding-left=8, padding-right=8, content-box (default)
    var flex_node = dom.Node.init(allocator, .element);
    var flex_sn = resolver.StyledNode{
        .node = &flex_node,
        .style = properties.ComputedStyle{
            .display = .flex,
            .flex_direction = .row,
            .width = .{ .value = 24, .unit = .px },
            .padding_left = .{ .value = 8, .unit = .px },
            .padding_right = .{ .value = 8, .unit = .px },
            // box_sizing defaults to .content_box
        },
        .children = &.{},
    };
    var flex_box = LayoutBox.init(.flexNode, &flex_sn);

    var fc = layout.FloatContext.init(allocator);
    defer fc.deinit();
    const ctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = 800,
        .viewport_height = 600,
        .float_ctx = &fc,
    };

    layoutFlexBox(&flex_box, &cb, ctx);

    // content-box: width:24px means content IS 24px, padding is extra
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), flex_box.dimensions.content.width, 0.01);
    // border-box width should be content(24) + padding(8+8) = 40
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), flex_box.dimensions.marginBox().width, 0.01);
}

test "RC-38: layoutFlexBox border-box width subtracts padding" {
    const allocator = std.testing.allocator;

    // Create a containing block with 200px content width
    var cb_node = dom.Node.init(allocator, .element);
    var cb_sn = resolver.StyledNode{
        .node = &cb_node,
        .style = properties.ComputedStyle{
            .display = .block,
        },
        .children = &.{},
    };
    var cb = LayoutBox.init(.blockNode, &cb_sn);
    cb.dimensions.content.width = 200;

    // Create the flex container: width=24px, padding-left=8, padding-right=8, border-box
    var flex_node = dom.Node.init(allocator, .element);
    var flex_sn = resolver.StyledNode{
        .node = &flex_node,
        .style = properties.ComputedStyle{
            .display = .flex,
            .flex_direction = .row,
            .width = .{ .value = 24, .unit = .px },
            .padding_left = .{ .value = 8, .unit = .px },
            .padding_right = .{ .value = 8, .unit = .px },
            .box_sizing = .border_box,
        },
        .children = &.{},
    };
    var flex_box = LayoutBox.init(.flexNode, &flex_sn);

    var fc = layout.FloatContext.init(allocator);
    defer fc.deinit();
    const ctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = 800,
        .viewport_height = 600,
        .float_ctx = &fc,
    };

    layoutFlexBox(&flex_box, &cb, ctx);

    // border-box: width:24px includes padding, so content = 24 - 8 - 8 = 8
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), flex_box.dimensions.content.width, 0.01);
    // border-box total should still be 24
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), flex_box.dimensions.marginBox().width, 0.01);
}

test "RC-38: layoutFlexBox auto-width still subtracts padding for content-box" {
    const allocator = std.testing.allocator;

    // Create a containing block with 200px content width
    var cb_node = dom.Node.init(allocator, .element);
    var cb_sn = resolver.StyledNode{
        .node = &cb_node,
        .style = properties.ComputedStyle{
            .display = .block,
        },
        .children = &.{},
    };
    var cb = LayoutBox.init(.blockNode, &cb_sn);
    cb.dimensions.content.width = 200;

    // Create the flex container: NO explicit width, padding-left=8, padding-right=8, content-box
    var flex_node = dom.Node.init(allocator, .element);
    var flex_sn = resolver.StyledNode{
        .node = &flex_node,
        .style = properties.ComputedStyle{
            .display = .flex,
            .flex_direction = .row,
            .padding_left = .{ .value = 8, .unit = .px },
            .padding_right = .{ .value = 8, .unit = .px },
            // width = null (auto), box_sizing = .content_box (default)
        },
        .children = &.{},
    };
    var flex_box = LayoutBox.init(.flexNode, &flex_sn);

    var fc = layout.FloatContext.init(allocator);
    defer fc.deinit();
    const ctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = 800,
        .viewport_height = 600,
        .float_ctx = &fc,
    };

    layoutFlexBox(&flex_box, &cb, ctx);

    // Auto width: specified_w = cb_width = 200, but content must fit inside
    // so content.width = 200 - 16 = 184
    try std.testing.expectApproxEqAbs(@as(f32, 184.0), flex_box.dimensions.content.width, 0.01);
}

test "RC-37: measureIntrinsicWidth takes max for block containers" {
    const allocator = std.testing.allocator;

    var child_node1 = dom.Node.init(allocator, .element);
    var child_node2 = dom.Node.init(allocator, .element);

    var child_sn1 = resolver.StyledNode{
        .node = &child_node1,
        .style = properties.ComputedStyle{
            .width = .{ .value = 30, .unit = .px },
        },
        .children = &.{},
    };
    var child_sn2 = resolver.StyledNode{
        .node = &child_node2,
        .style = properties.ComputedStyle{
            .width = .{ .value = 50, .unit = .px },
        },
        .children = &.{},
    };

    var child1 = LayoutBox.init(.blockNode, &child_sn1);
    child1.dimensions.content.width = 30;

    var child2 = LayoutBox.init(.blockNode, &child_sn2);
    child2.dimensions.content.width = 50;

    var parent_node = dom.Node.init(allocator, .element);
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = properties.ComputedStyle{
            .display = .block,
        },
        .children = &.{},
    };
    var parent = LayoutBox.init(.blockNode, &parent_sn);

    parent.children.append(allocator, &child1) catch unreachable;
    parent.children.append(allocator, &child2) catch unreachable;
    defer parent.children.deinit(allocator);

    // Block container: intrinsic width should be MAX = 50, not SUM = 80
    const width = measureIntrinsicWidth(&parent);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), width, 0.01);
}

test "RC-40: parse align-self property" {
    var style = properties.ComputedStyle{};
    const allocator = std.testing.allocator;
    try std.testing.expect(style.align_self == null); // default is null (auto)

    try style.applyProperty("align-self", "center", allocator);
    try std.testing.expectEqual(properties.AlignItems.center, style.align_self.?);

    try style.applyProperty("align-self", "auto", allocator);
    try std.testing.expect(style.align_self == null);

    try style.applyProperty("align-self", "flex-end", allocator);
    try std.testing.expectEqual(properties.AlignItems.flex_end, style.align_self.?);

    try style.applyProperty("align-self", "stretch", allocator);
    try std.testing.expectEqual(properties.AlignItems.stretch, style.align_self.?);
}

test "RC-40: align-self center overrides parent align-items stretch" {
    const allocator = std.testing.allocator;

    // Parent: row flex, h=50, align-items: stretch
    var parent_node = dom.Node.init(allocator, .element);
    var parent_style = properties.ComputedStyle{};
    parent_style.display = .flex;
    parent_style.flex_direction = .row;
    parent_style.width = .{ .value = 100, .unit = .px };
    parent_style.height = .{ .value = 50, .unit = .px };
    parent_style.align_items = .stretch;
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = parent_style,
        .children = &.{},
    };

    // Child: h=24, align-self: center
    var child_node = dom.Node.init(allocator, .element);
    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.height = .{ .value = 24, .unit = .px };
    child_style.align_self = .center;
    var child_sn = resolver.StyledNode{
        .node = &child_node,
        .style = child_style,
        .children = &.{},
    };

    var child_box = LayoutBox.init(.blockNode, &child_sn);
    var parent_box = LayoutBox.init(.flexNode, &parent_sn);
    parent_box.children.append(allocator, &child_box) catch unreachable;
    defer parent_box.children.deinit(allocator);

    var float_ctx = layout.FloatContext.init(allocator);
    defer float_ctx.deinit();
    const ctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = 1200,
        .viewport_height = 800,
        .float_ctx = &float_ctx,
    };

    layoutFlexBox(&parent_box, &parent_box, ctx);

    // Child should NOT be stretched (align-self:center overrides stretch)
    try std.testing.expectEqual(@as(f32, 24), child_box.dimensions.content.height);
    // Child should be centered: y offset = (50-24)/2 = 13
    const child_content_y = child_box.dimensions.content.y;
    const parent_content_y = parent_box.dimensions.content.y;
    try std.testing.expectEqual(@as(f32, 13), child_content_y - parent_content_y);
}

test "RC-40: align-self null inherits parent align-items center" {
    const allocator = std.testing.allocator;

    var parent_node = dom.Node.init(allocator, .element);
    var parent_style = properties.ComputedStyle{};
    parent_style.display = .flex;
    parent_style.flex_direction = .row;
    parent_style.width = .{ .value = 100, .unit = .px };
    parent_style.height = .{ .value = 50, .unit = .px };
    parent_style.align_items = .center;
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = parent_style,
        .children = &.{},
    };

    var child_node = dom.Node.init(allocator, .element);
    var child_style = properties.ComputedStyle{};
    child_style.display = .block;
    child_style.height = .{ .value = 20, .unit = .px };
    // align_self is null (default) -> inherits parent's center
    var child_sn = resolver.StyledNode{
        .node = &child_node,
        .style = child_style,
        .children = &.{},
    };

    var child_box = LayoutBox.init(.blockNode, &child_sn);
    var parent_box = LayoutBox.init(.flexNode, &parent_sn);
    parent_box.children.append(allocator, &child_box) catch unreachable;
    defer parent_box.children.deinit(allocator);

    var float_ctx = layout.FloatContext.init(allocator);
    defer float_ctx.deinit();
    const ctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = 1200,
        .viewport_height = 800,
        .float_ctx = &float_ctx,
    };

    layoutFlexBox(&parent_box, &parent_box, ctx);

    // Child centered: y offset = (50-20)/2 = 15
    const child_content_y = child_box.dimensions.content.y;
    const parent_content_y = parent_box.dimensions.content.y;
    try std.testing.expectEqual(@as(f32, 15), child_content_y - parent_content_y);
}

test "RC-41: column flex-grow readjusts after auto-height siblings laid out" {
    const allocator = std.testing.allocator;

    // Column flex container, h=100
    var parent_node = dom.Node.init(allocator, .element);
    var parent_style = properties.ComputedStyle{};
    parent_style.display = .flex;
    parent_style.flex_direction = .column;
    parent_style.width = .{ .value = 100, .unit = .px };
    parent_style.height = .{ .value = 100, .unit = .px };
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = parent_style,
        .children = &.{},
    };

    // Child A: explicit height 30px
    var child_a_node = dom.Node.init(allocator, .element);
    var child_a_style = properties.ComputedStyle{};
    child_a_style.display = .block;
    child_a_style.height = .{ .value = 30, .unit = .px };
    var child_a_sn = resolver.StyledNode{
        .node = &child_a_node,
        .style = child_a_style,
        .children = &.{},
    };

    var child_a_box = LayoutBox.init(.blockNode, &child_a_sn);

    // Child B: flex-grow: 1 (should get remaining 70px)
    var child_b_node = dom.Node.init(allocator, .element);
    var child_b_style = properties.ComputedStyle{};
    child_b_style.display = .block;
    child_b_style.flex_grow = 1.0;
    var child_b_sn = resolver.StyledNode{
        .node = &child_b_node,
        .style = child_b_style,
        .children = &.{},
    };

    var child_b_box = LayoutBox.init(.blockNode, &child_b_sn);

    var parent_box = LayoutBox.init(.flexNode, &parent_sn);
    parent_box.children.append(allocator, &child_a_box) catch unreachable;
    parent_box.children.append(allocator, &child_b_box) catch unreachable;
    defer parent_box.children.deinit(allocator);

    var float_ctx = layout.FloatContext.init(allocator);
    defer float_ctx.deinit();
    const ctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = 1200,
        .viewport_height = 800,
        .float_ctx = &float_ctx,
    };

    layoutFlexBox(&parent_box, &parent_box, ctx);

    // Child A: h=30 (explicit)
    try std.testing.expectEqual(@as(f32, 30), child_a_box.dimensions.content.height);
    // Child B: h=70 (remaining space after A)
    try std.testing.expectEqual(@as(f32, 70), child_b_box.dimensions.content.height);
}

test "RC-43: three-level flex hierarchy stretch propagation with min-height" {
    // Models the google.com scenario:
    //   .RNNXgb (row flex, min-height:50px, no explicit height)
    //     └─ .SDkEP (row flex, no explicit height → should stretch to h=50)
    //         └─ .a4bIc (block, no explicit height → should stretch to h=50)
    const allocator = std.testing.allocator;

    // Grandchild: block element, no explicit height (content height = 0)
    var gc_node = dom.Node.init(allocator, .element);
    var gc_style = properties.ComputedStyle{};
    gc_style.display = .block;
    // No explicit height — should get stretched
    var gc_sn = resolver.StyledNode{
        .node = &gc_node,
        .style = gc_style,
        .children = &.{},
    };
    var gc_box = LayoutBox.init(.blockNode, &gc_sn);

    // Child: row flex container, no explicit height (should stretch to parent's min-height)
    var child_node = dom.Node.init(allocator, .element);
    var child_style = properties.ComputedStyle{};
    child_style.display = .flex;
    child_style.flex_direction = .row;
    // No explicit height — should be stretched by parent
    var child_sn = resolver.StyledNode{
        .node = &child_node,
        .style = child_style,
        .children = &.{},
    };
    var child_box = LayoutBox.init(.flexNode, &child_sn);
    child_box.children.append(allocator, &gc_box) catch unreachable;
    defer child_box.children.deinit(allocator);

    // Parent: row flex container, min-height: 50px, no explicit height
    var parent_node = dom.Node.init(allocator, .element);
    var parent_style = properties.ComputedStyle{};
    parent_style.display = .flex;
    parent_style.flex_direction = .row;
    parent_style.min_height = .{ .value = 50, .unit = .px };
    // No explicit height — this triggers the bug: container_cross_size = 0
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = parent_style,
        .children = &.{},
    };
    var parent_box = LayoutBox.init(.flexNode, &parent_sn);
    parent_box.children.append(allocator, &child_box) catch unreachable;
    defer parent_box.children.deinit(allocator);

    var float_ctx = layout.FloatContext.init(allocator);
    defer float_ctx.deinit();
    const ctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = 1200,
        .viewport_height = 800,
        .float_ctx = &float_ctx,
    };

    layoutFlexBox(&parent_box, &parent_box, ctx);

    // Parent should have h=50 (from min-height)
    try std.testing.expectEqual(@as(f32, 50), parent_box.dimensions.content.height);
    // Child should be stretched to h=50 (no explicit height, align-items:stretch default)
    try std.testing.expectEqual(@as(f32, 50), child_box.dimensions.content.height);
    // Grandchild should be stretched to h=50 (propagated through child flex container)
    try std.testing.expectEqual(@as(f32, 50), gc_box.dimensions.content.height);
}

test "RC-44: RC-29 re-layout passes child as containing block so descendants see correct flex-grow width" {
    // Models the google.com scenario where RC-29 recalculates flex-grow
    // after Pass 2b shrink-to-fit. The re-layout must use the child as
    // its own containing block so descendants see the corrected width.
    //
    //   parent (row flex, w=600)
    //     ├─ child_a (flex-grow:1, flex container) → should get w≈400
    //     │   └─ grandchild (width:100%) → should match child_a's width
    //     └─ child_b (auto-width, flex:0 0 auto, contains a 200px block)
    //         └─ inner_b (w=200)
    //
    // child_b triggers Pass 2b shrink-to-fit (auto-width, no flex-basis),
    // which triggers RC-29 recalculation. RC-29 must pass child_a as its
    // own containing block when re-laying out, so grandchild sees the
    // corrected flex-grow width, not the parent's full width.
    const allocator = std.testing.allocator;

    // Grandchild: block element with width:100% of its parent (child_a)
    var gc_node = dom.Node.init(allocator, .element);
    var gc_style = properties.ComputedStyle{};
    gc_style.display = .block;
    gc_style.width = .{ .value = 100, .unit = .percent };
    var gc_sn = resolver.StyledNode{
        .node = &gc_node,
        .style = gc_style,
        .children = &.{},
    };
    var gc_box = LayoutBox.init(.blockNode, &gc_sn);

    // Child A: flex-grow:1, flex container (row) — contains grandchild
    var child_a_node = dom.Node.init(allocator, .element);
    var child_a_style = properties.ComputedStyle{};
    child_a_style.display = .flex;
    child_a_style.flex_direction = .row;
    child_a_style.flex_grow = 1.0;
    var child_a_sn = resolver.StyledNode{
        .node = &child_a_node,
        .style = child_a_style,
        .children = &.{},
    };
    var child_a_box = LayoutBox.init(.flexNode, &child_a_sn);
    child_a_box.children.append(allocator, &gc_box) catch unreachable;
    defer child_a_box.children.deinit(allocator);

    // Inner B: a block child of child_b with explicit width 200px.
    // This gives child_b measurable content for Pass 2b shrink-to-fit.
    var inner_b_node = dom.Node.init(allocator, .element);
    var inner_b_style = properties.ComputedStyle{};
    inner_b_style.display = .block;
    inner_b_style.width = .{ .value = 200, .unit = .px };
    var inner_b_sn = resolver.StyledNode{
        .node = &inner_b_node,
        .style = inner_b_style,
        .children = &.{},
    };
    var inner_b_box = LayoutBox.init(.blockNode, &inner_b_sn);

    // Child B: auto-width flex item (flex:0 0 auto) containing inner_b.
    // No flex-basis, no explicit width → base_size=0, not locked by grow.
    // Pass 2b will shrink-to-fit it to 200px (inner_b's width).
    var child_b_node = dom.Node.init(allocator, .element);
    var child_b_style = properties.ComputedStyle{};
    child_b_style.display = .flex;
    child_b_style.flex_direction = .row;
    child_b_style.flex_grow = 0;
    child_b_style.flex_shrink = 0;
    var child_b_sn = resolver.StyledNode{
        .node = &child_b_node,
        .style = child_b_style,
        .children = &.{},
    };
    var child_b_box = LayoutBox.init(.flexNode, &child_b_sn);
    child_b_box.children.append(allocator, &inner_b_box) catch unreachable;
    defer child_b_box.children.deinit(allocator);

    // Parent: row flex container, w=600
    var parent_node = dom.Node.init(allocator, .element);
    var parent_style = properties.ComputedStyle{};
    parent_style.display = .flex;
    parent_style.flex_direction = .row;
    parent_style.width = .{ .value = 600, .unit = .px };
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = parent_style,
        .children = &.{},
    };
    var parent_box = LayoutBox.init(.flexNode, &parent_sn);
    parent_box.children.append(allocator, &child_a_box) catch unreachable;
    parent_box.children.append(allocator, &child_b_box) catch unreachable;
    defer parent_box.children.deinit(allocator);

    // Containing block for the parent (simulates viewport)
    var cb_node = dom.Node.init(allocator, .element);
    var cb_style = properties.ComputedStyle{};
    cb_style.display = .block;
    var cb_sn = resolver.StyledNode{
        .node = &cb_node,
        .style = cb_style,
        .children = &.{},
    };
    var cb_box = LayoutBox.init(.blockNode, &cb_sn);
    cb_box.dimensions.content.width = 1200;

    var float_ctx = layout.FloatContext.init(allocator);
    defer float_ctx.deinit();
    const ctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = 1200,
        .viewport_height = 800,
        .float_ctx = &float_ctx,
    };

    layoutFlexBox(&parent_box, &cb_box, ctx);

    // Child B should be shrink-to-fit at 200px (from inner_b)
    try std.testing.expectEqual(@as(f32, 200), child_b_box.dimensions.content.width);
    // Child A should get w=400 (600 - 200) from flex-grow after RC-29
    try std.testing.expectEqual(@as(f32, 400), child_a_box.dimensions.content.width);
    // Grandchild (100% of child_a) should see the corrected width, NOT parent's 600
    try std.testing.expectEqual(@as(f32, 400), gc_box.dimensions.content.width);
}

test "VR-6: measureIntrinsicWidth respects min-width on auto-width children" {
    const allocator = std.testing.allocator;

    // Create child DOM node — auto-width, but with min-width: 85px border-box
    var child_node = dom.Node.init(allocator, .element);
    var child_sn = resolver.StyledNode{
        .node = &child_node,
        .style = properties.ComputedStyle{
            .min_width = .{ .value = 85, .unit = .px },
            .box_sizing = .border_box,
            .padding_left = .{ .value = 12, .unit = .px },
            .padding_right = .{ .value = 12, .unit = .px },
        },
        .children = &.{},
    };

    // The child LayoutBox has NO explicit width — auto-width path.
    // It has a text run of 43px simulating "Sign in" text.
    var child_box = LayoutBox.init(.blockNode, &child_sn);
    child_box.dimensions.padding.left = 12;
    child_box.dimensions.padding.right = 12;
    // Add a text run to produce inner_width=43 from recursion
    child_box.text_runs.append(allocator, .{
        .text = "Sign in",
        .styled_node = &child_sn,
        .x = 0,
        .y = 0,
        .width = 43,
    }) catch unreachable;
    defer child_box.text_runs.deinit(allocator);

    // Create a row flex parent
    var parent_node = dom.Node.init(allocator, .element);
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = properties.ComputedStyle{
            .display = .flex,
            .flex_direction = .row,
        },
        .children = &.{},
    };
    var parent_box = LayoutBox.init(.flexNode, &parent_sn);

    parent_box.children.append(allocator, &child_box) catch unreachable;
    defer parent_box.children.deinit(allocator);

    // Without fix: inner_width=43, child_width = 43 + 12 + 12 = 67
    // With fix: min-width=85 border-box, so child_width = max(67, 85) = 85
    const width = measureIntrinsicWidth(&parent_box);
    try std.testing.expectApproxEqAbs(@as(f32, 85.0), width, 0.01);
}

test "VR-6: measureIntrinsicWidth respects min-width content-box" {
    const allocator = std.testing.allocator;

    // Create child DOM node — auto-width, min-width: 60px content-box (default)
    var child_node = dom.Node.init(allocator, .element);
    var child_sn = resolver.StyledNode{
        .node = &child_node,
        .style = properties.ComputedStyle{
            .min_width = .{ .value = 60, .unit = .px },
            // box_sizing defaults to .content_box
            .padding_left = .{ .value = 12, .unit = .px },
            .padding_right = .{ .value = 12, .unit = .px },
        },
        .children = &.{},
    };

    var child_box = LayoutBox.init(.blockNode, &child_sn);
    child_box.dimensions.padding.left = 12;
    child_box.dimensions.padding.right = 12;
    // Add a text run to produce inner_width=43 from recursion
    child_box.text_runs.append(allocator, .{
        .text = "Sign in",
        .styled_node = &child_sn,
        .x = 0,
        .y = 0,
        .width = 43,
    }) catch unreachable;
    defer child_box.text_runs.deinit(allocator);

    // Create a row flex parent
    var parent_node = dom.Node.init(allocator, .element);
    var parent_sn = resolver.StyledNode{
        .node = &parent_node,
        .style = properties.ComputedStyle{
            .display = .flex,
            .flex_direction = .row,
        },
        .children = &.{},
    };
    var parent_box = LayoutBox.init(.flexNode, &parent_sn);

    parent_box.children.append(allocator, &child_box) catch unreachable;
    defer parent_box.children.deinit(allocator);

    // Without fix: inner_width=43, child_width = 43 + 12 + 12 = 67
    // With fix: min-width=60 content-box, so total = max(67, 60 + 24) = max(67, 84) = 84
    const width = measureIntrinsicWidth(&parent_box);
    try std.testing.expectApproxEqAbs(@as(f32, 84.0), width, 0.01);
}
