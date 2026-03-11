const std = @import("std");
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

    // Resolve height BEFORE children if it's a fixed value or percentage (not auto)
    var is_auto_height = true;
    if (box.styled_node) |sn| {
        if (sn.style.height != null) {
            is_auto_height = false;
            block_metrics.calculateHeight(box, containing_block, ctx);
        }
    }

    layoutChildren(box, ctx);

    if (locked_height) {
        box.dimensions.content.height = preserved_height;
    } else if (is_auto_height) {
        block_metrics.calculateHeight(box, containing_block, ctx);
    }

    // Resolve intrinsic image dimensions if not already set by CSS
    if (box.styled_node) |sn| {
        if (sn.node.tag == .img) {
            if (sn.style.width == null) {
                if (sn.node.getAttribute("width")) |w_str| {
                    if (std.fmt.parseFloat(f32, w_str)) |w| {
                        box.dimensions.content.width = w;
                        box.lock_content_width = true;
                    } else |_| {}
                }
            }
            if (sn.style.height == null) {
                if (sn.node.getAttribute("height")) |h_str| {
                    if (std.fmt.parseFloat(f32, h_str)) |h| {
                        box.dimensions.content.height = h;
                        box.lock_content_height = true;
                    } else |_| {}
                }
            }
        }
        if (sn.node.tag == .input) {
            if (sn.node.getAttribute("value")) |val| {
                const text_measure = @import("text_measure.zig");
                const fs = sn.style.font_size.value;
                const fw = sn.style.font_weight;
                const tw = text_measure.measureTextWidth(val, fs, fw);
                
                // Center the text
                const ox = box.dimensions.content.x + (box.dimensions.content.width - tw) / 2.0;
                const string_lh = fs * 1.2;
                const oy = box.dimensions.content.y + (box.dimensions.content.height - string_lh) / 2.0;

                box.text_runs.append(ctx.allocator, .{
                    .text = val,
                    .styled_node = sn,
                    .layout_box = box,
                    .x = @max(box.dimensions.content.x, ox),
                    .y = @max(box.dimensions.content.y, oy),
                    .width = tw,
                    .line_height = string_lh,
                }) catch {};
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
    const is_shrink_to_fit = (box.box_type == .inlineBlockNode) and (!box.lock_content_width);
    box.dimensions.content.height = 0;
    if (is_shrink_to_fit) box.dimensions.content.width = 0;
    
    var max_child_width: f32 = 0;
    var pending_margin: f32 = 0;
    var is_at_parent_top = true;
    
    const is_root = box.styled_node != null and (box.styled_node.?.node.parent == null or box.styled_node.?.node.tag == .html);
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
            if (child.box_type == .tableNode) {
                @import("table.zig").layoutTable(child, box, ctx);
            } else {
                layoutBlock(child, box, ctx);
            }
            position.applyPositioning(child, ctx);
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
        
        const child_full_width = child.dimensions.marginBox().width;
        if (child_full_width > 2000) {
            const tag = if (child.styled_node) |sn| sn.node.tag_name_str orelse "unknown" else "anon";
            std.debug.print("Block: child '{s}' causing large width: {d} at relative y={d}\n", .{ tag, child_full_width, box.dimensions.content.height });
        }
        max_child_width = @max(max_child_width, child_full_width);

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

        // Apply Block Centering (e.g. for `<center>` tag) unconditionally after Y positioning
        if (box.styled_node) |sn| {
            if (sn.style.text_align == .center) {
                const child_outer_w = child.dimensions.marginBox().width;
                const parent_w = box.dimensions.content.width;
                if (child_outer_w < parent_w) {
                    const center_offset = (parent_w - child_outer_w) / 2.0;
                    block_metrics.shiftBoxX(child, center_offset);
                }
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

    if (is_shrink_to_fit) {
        box.dimensions.content.width = max_child_width;
    }
}
