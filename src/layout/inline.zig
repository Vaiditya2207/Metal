const std = @import("std");
const box_mod = @import("box.zig");
const text_measure = @import("text_measure.zig");
const resolver = @import("../css/resolver.zig");
const properties = @import("../css/properties.zig");
const block = @import("block.zig");

fn shiftBox(box: *box_mod.LayoutBox, dx: f32, dy: f32) void {
    box.dimensions.content.x += dx;
    box.dimensions.content.y += dy;
    for (box.text_runs.items) |*run| {
        run.x += dx;
        run.y += dy;
    }
    for (box.children.items) |child| {
        shiftBox(child, dx, dy);
    }
}

const TextSegment = struct {
    text: []const u8,
    styled_node: *const resolver.StyledNode,
    layout_box: *box_mod.LayoutBox,
    font_size: f32,
    font_weight: f32,
    line_height: f32,
    white_space: properties.WhiteSpace,
    is_inline_block: bool = false,
};

fn collectTextSegments(
    box: *box_mod.LayoutBox,
    segments: *std.ArrayListUnmanaged(TextSegment),
    allocator: std.mem.Allocator,
) void {
    if (box.box_type == .inlineBlockNode or box.box_type == .blockNode or box.box_type == .flexNode) {
        if (box.styled_node) |sn| {
            segments.append(allocator, .{
                .text = "",
                .styled_node = sn,
                .layout_box = box,
                .font_size = sn.style.font_size.value,
                .font_weight = sn.style.font_weight,
                .line_height = @max(box.intrinsic_height, sn.style.line_height * sn.style.font_size.value),
                .white_space = sn.style.white_space,
                .is_inline_block = true,
            }) catch return;
        }
        return; // do not dig into inlineBlockNode/blockNode's children for text extraction
    }

    if (box.styled_node) |sn| {
        if (sn.node.node_type == .text) {
            if (sn.node.data) |data| {
                const trimmed = std.mem.trim(u8, data, " \t\n\r");
                if (trimmed.len > 0 or sn.style.white_space == .pre) {
                    segments.append(allocator, .{
                        .text = data,
                        .styled_node = sn,
                        .layout_box = box,
                        .font_size = sn.style.font_size.value,
                        .font_weight = sn.style.font_weight,
                        .line_height = sn.style.line_height * sn.style.font_size.value,
                        .white_space = sn.style.white_space,
                        .is_inline_block = false,
                    }) catch return;
                }
            }
            return;
        }

        if (sn.node.node_type == .element) {
            if (std.mem.eql(u8, sn.node.tag_name_str orelse "", "br")) {
                segments.append(allocator, .{
                    .text = "\n",
                    .styled_node = sn,
                    .layout_box = box,
                    .font_size = sn.style.font_size.value,
                    .font_weight = sn.style.font_weight,
                    .line_height = sn.style.line_height * sn.style.font_size.value,
                    .white_space = .pre,
                    .is_inline_block = false,
                }) catch return;
                return;
            }
        }
    }
    for (box.children.items) |child| {
        collectTextSegments(child, segments, allocator);
    }
}

fn expandBoxRect(box: *box_mod.LayoutBox, abs_x: f32, abs_y: f32, w: f32, h: f32) void {
    // We used to skip anonymous blocks here, but they need to encompass their inline content
    // so they can propagate dimensions up to their block parents.
    
    if (box.dimensions.content.width == 0 and box.dimensions.content.height == 0) {
        box.dimensions.content.x = abs_x;
        box.dimensions.content.y = abs_y;
        box.dimensions.content.width = w;
        box.dimensions.content.height = h;
    } else {
        const old_r = box.dimensions.content.x + box.dimensions.content.width;
        const old_b = box.dimensions.content.y + box.dimensions.content.height;
        const new_r = @max(old_r, abs_x + w);
        const new_b = @max(old_b, abs_y + h);
        
        // We only expand width/height, we DO NOT pull the box's established X/Y coordinate.
        // The parent determines our X/Y. We just tell it how much space we occupied.
        box.dimensions.content.width = @max(box.dimensions.content.width, new_r - box.dimensions.content.x);
        box.dimensions.content.height = @max(box.dimensions.content.height, new_b - box.dimensions.content.y);
    }

    if (box.parent) |p| {
        expandBoxRect(p, abs_x, abs_y, w, h);
    }
}

fn resetChildDimensions(box: *box_mod.LayoutBox) void {
    box.dimensions.content.x = 0;
    box.dimensions.content.y = 0;
    if (!box.lock_content_width) {
        box.dimensions.content.width = 0;
    }
    if (!box.lock_content_height) {
        box.dimensions.content.height = 0;
    }
    for (box.children.items) |child| {
        resetChildDimensions(child);
    }
}

pub fn layoutInlineBlock(layout_box: *box_mod.LayoutBox, parent_font_size: f32, ctx: @import("layout.zig").LayoutContext) void {
    const allocator = ctx.allocator;
    // For inline-blocks with auto width (0), use the parent's width as the wrapping limit
    var container_width = layout_box.dimensions.content.width;
    if (container_width == 0) {
        var curr = layout_box.parent;
        while (curr) |p| {
            if (p.dimensions.content.width > 0) {
                container_width = p.dimensions.content.width;
                break;
            }
            curr = p.parent;
        }
    }
    if (container_width == 0) container_width = ctx.viewport_width;
    if (container_width > ctx.viewport_width * 2.0) {
         // std.debug.print("Inline: Capping extreme container_width {d} to {d}\n", .{ container_width, ctx.viewport_width });
         container_width = ctx.viewport_width;
    }
    const anon_abs_x = layout_box.dimensions.content.x;
    const anon_abs_y = layout_box.dimensions.content.y;

    var cursor_x: f32 = 0;
    var cursor_y: f32 = 0;
    var max_line_width: f32 = 0;
    var current_line_height: f32 = parent_font_size * 1.2;

    for (layout_box.children.items) |child| {
        resetChildDimensions(child);
    }
    
    layout_box.text_runs.clearRetainingCapacity();

    var segments = std.ArrayListUnmanaged(TextSegment){};
    var buf: [16384]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    
    collectTextSegments(layout_box, &segments, fba.allocator());

    var line_start_idx: usize = 0;
    var current_run_idx: usize = 0;
    var last_styled_node: ?*const resolver.StyledNode = null;

    for (segments.items) |seg| {
        const space_width = text_measure.measureTextWidth(" ", seg.font_size, seg.font_weight);

        // Get available width for the current line
        var available = if (ctx.float_ctx) |fc| 
            fc.getAvailableWidth(anon_abs_y + cursor_y, current_line_height, container_width, anon_abs_x)
        else 
            @import("layout.zig").AvailableSpace{ .x_offset = 0, .width = container_width };

        if (last_styled_node != null and last_styled_node != seg.styled_node and cursor_x > 0) {
            cursor_x += space_width;
        }
        last_styled_node = seg.styled_node;

        if (seg.is_inline_block) {
            block.layoutBlock(seg.layout_box, layout_box, ctx);

            var block_w = seg.layout_box.dimensions.marginBox().width;
            if (block_w == 0) block_w = seg.layout_box.calculateIntrinsicWidth();
            
            // diagnostic
            if (seg.layout_box.styled_node != null and seg.layout_box.styled_node.?.node.tag == .input) {
                std.debug.print("INPUT INLINE: cursor_x={d}, block_w={d}, avail_w={d}\n", .{ cursor_x, block_w, available.width });
            }
            
            var block_h = seg.layout_box.dimensions.marginBox().height;
            if (block_h == 0) block_h = seg.line_height;

            // If it doesn't fit in the current shortened line box, shift down
            if (cursor_x + block_w > available.width and cursor_x > 0) {
                alignLine(layout_box, line_start_idx, current_run_idx, available.width, cursor_x, available.x_offset);
                line_start_idx = current_run_idx;
                
                max_line_width = @max(max_line_width, cursor_x);
                cursor_x = 0;
                cursor_y += current_line_height;
                current_line_height = block_h;
                
                // Re-query available width for the new line
                available = if (ctx.float_ctx) |fc| 
                    fc.getAvailableWidth(anon_abs_y + cursor_y, current_line_height, container_width, anon_abs_x)
                else 
                    @import("layout.zig").AvailableSpace{ .x_offset = 0, .width = container_width };
            }

            // If it STILL doesn't fit (even at cursor_x = 0), and there are floats, shift down past floats
            while (cursor_x + block_w > available.width and ctx.float_ctx != null) {
                if (available.width >= container_width) break;
                const prev_y = cursor_y;
                cursor_y += 1.0; // Simple downward search (optimization: jump to next float bottom in future)
                available = ctx.float_ctx.?.getAvailableWidth(anon_abs_y + cursor_y, current_line_height, container_width, anon_abs_x);
                if (cursor_y - prev_y > 1000) break; // Safety break
            }

            const target_x = anon_abs_x + available.x_offset + cursor_x + seg.layout_box.dimensions.margin.left + seg.layout_box.dimensions.border.left + seg.layout_box.dimensions.padding.left;
            const target_y = anon_abs_y + cursor_y + seg.layout_box.dimensions.margin.top + seg.layout_box.dimensions.border.top + seg.layout_box.dimensions.padding.top;
            
            const dx = target_x - seg.layout_box.dimensions.content.x;
            const dy = target_y - seg.layout_box.dimensions.content.y;
            shiftBox(seg.layout_box, dx, dy);

            layout_box.text_runs.append(allocator, .{
                .text = "",
                .styled_node = seg.styled_node,
                .layout_box = seg.layout_box,
                .x = anon_abs_x + available.x_offset + cursor_x,
                .y = anon_abs_y + cursor_y,
                .width = block_w,
                .line_height = block_h,
            }) catch continue;

            current_run_idx += 1;
            cursor_x += block_w;
            current_line_height = @max(current_line_height, block_h);
            continue;
        }

        if (std.mem.eql(u8, seg.text, "\n")) {
            alignLine(layout_box, line_start_idx, current_run_idx, available.width, cursor_x, available.x_offset);
            line_start_idx = current_run_idx;
            
            max_line_width = @max(max_line_width, cursor_x);
            cursor_x = 0;
            cursor_y += current_line_height;
            current_line_height = seg.line_height;
            continue;
        }

        const text = if (seg.white_space != .pre) std.mem.trim(u8, seg.text, " \t\n\r") else seg.text;
        if (text.len == 0 and seg.white_space != .pre) continue;

        var iter = std.mem.splitAny(u8, text, " \t\n\r");
        var first_word = true;
        
        while (iter.next()) |word| {
            if (word.len == 0 and seg.white_space != .pre) continue;
            const word_width = text_measure.measureTextWidth(word, seg.font_size, seg.font_weight);

            if (!first_word and cursor_x > 0) {
                cursor_x += space_width;
            }

            // If it doesn't fit, shift down
            if (cursor_x + word_width > available.width and cursor_x > 0 and seg.white_space != .nowrap and seg.white_space != .pre) {
                alignLine(layout_box, line_start_idx, current_run_idx, available.width, cursor_x, available.x_offset);
                line_start_idx = current_run_idx;
                
                max_line_width = @max(max_line_width, cursor_x);
                cursor_x = 0;
                cursor_y += current_line_height;
                current_line_height = seg.line_height;
                
                available = if (ctx.float_ctx) |fc| 
                    fc.getAvailableWidth(anon_abs_y + cursor_y, current_line_height, container_width, anon_abs_x)
                else 
                    @import("layout.zig").AvailableSpace{ .x_offset = 0, .width = container_width };
            }

            // If it STILL doesn't fit, shift down past floats
            while (cursor_x + word_width > available.width and ctx.float_ctx != null and seg.white_space != .nowrap and seg.white_space != .pre) {
                if (available.width >= container_width) break;
                const prev_y = cursor_y;
                cursor_y += 1.0;
                available = ctx.float_ctx.?.getAvailableWidth(anon_abs_y + cursor_y, current_line_height, container_width, anon_abs_x);
                if (cursor_y - prev_y > 1000) break;
            }

            layout_box.text_runs.append(allocator, .{
                .text = word,
                .styled_node = seg.styled_node,
                .layout_box = seg.layout_box,
                .x = anon_abs_x + available.x_offset + cursor_x,
                .y = anon_abs_y + cursor_y,
                .width = word_width,
                .line_height = seg.line_height,
            }) catch continue;

            current_run_idx += 1;
            cursor_x += word_width;
            first_word = false;
            current_line_height = @max(current_line_height, seg.line_height);
        }
    }
    
    // Final line alignment
    const final_available = if (ctx.float_ctx) |fc| 
        fc.getAvailableWidth(anon_abs_y + cursor_y, current_line_height, container_width, anon_abs_x)
    else 
        @import("layout.zig").AvailableSpace{ .x_offset = 0, .width = container_width };
    alignLine(layout_box, line_start_idx, current_run_idx, final_available.width, cursor_x, final_available.x_offset);
    max_line_width = @max(max_line_width, cursor_x);
    
    // AFTER alignment, expand rects for inline boundaries
    for (layout_box.text_runs.items) |run| {
        if (run.layout_box.box_type == .inlineBlockNode) {
            if (run.layout_box.parent) |p| {
                expandBoxRect(p, run.x, run.y, run.width, run.line_height);
            }
        } else {
            expandBoxRect(run.layout_box, run.x, run.y, run.width, run.line_height);
        }
    }
    
    layout_box.dimensions.content.width = max_line_width;
    layout_box.dimensions.content.height = cursor_y + current_line_height;
    layout_box.lock_content_width = true;
    layout_box.lock_content_height = true;
}

fn alignLine(box: *box_mod.LayoutBox, start_idx: usize, end_idx: usize, available_width: f32, line_width: f32, x_offset: f32) void {
    if (start_idx >= end_idx) return;
    
    var text_align: properties.TextAlign = .left;
     if (box.parent) |p| {
         if (p.styled_node) |sn| {
             text_align = sn.style.text_align;
         }
     }
    
    var align_offset: f32 = 0;
    if (text_align == .center) {
        align_offset = @max(0, (available_width - line_width) / 2.0);
    } else if (text_align == .right) {
        align_offset = @max(0, available_width - line_width);
    }
    
    const total_offset = x_offset + align_offset;
    if (total_offset > 0) {
        // We already added x_offset in layout_box.text_runs.append in some cases? 
        // Actually I added available.x_offset in the append calls. 
        // Wait, if I added it in append, I should ONLY add align_offset here.
        // Let's re-examine.
    }
    
    if (align_offset > 0) {
        var i: usize = start_idx;
        while (i < end_idx) : (i += 1) {
            box.text_runs.items[i].x += align_offset;
            const run_box = box.text_runs.items[i].layout_box;
            if (run_box.box_type == .inlineBlockNode) {
                shiftBox(run_box, align_offset, 0);
            }
        }
    }
}
