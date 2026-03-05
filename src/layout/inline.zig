const std = @import("std");
const box_mod = @import("box.zig");
const text_measure = @import("text_measure.zig");
const resolver = @import("../css/resolver.zig");
const properties = @import("../css/properties.zig");

const TextSegment = struct {
    text: []const u8,
    styled_node: *const resolver.StyledNode,
    layout_box: *box_mod.LayoutBox,
    font_size: f32,
    font_weight: f32,
    line_height: f32,
    white_space: properties.WhiteSpace,
};

fn collectTextSegments(
    box: *box_mod.LayoutBox,
    segments: *std.ArrayListUnmanaged(TextSegment),
    allocator: std.mem.Allocator,
) void {
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
    if (box.box_type == .anonymousBlock) return;
    
    if (box.dimensions.content.width == 0 and box.dimensions.content.height == 0) {
        box.dimensions.content.x = abs_x;
        box.dimensions.content.y = abs_y;
        box.dimensions.content.width = w;
        box.dimensions.content.height = h;
    } else {
        const old_r = box.dimensions.content.x + box.dimensions.content.width;
        const old_b = box.dimensions.content.y + box.dimensions.content.height;
        box.dimensions.content.x = @min(box.dimensions.content.x, abs_x);
        box.dimensions.content.y = @min(box.dimensions.content.y, abs_y);
        const new_r = @max(old_r, abs_x + w);
        const new_b = @max(old_b, abs_y + h);
        box.dimensions.content.width = new_r - box.dimensions.content.x;
        box.dimensions.content.height = new_b - box.dimensions.content.y;
    }

    if (box.parent) |p| {
        expandBoxRect(p, abs_x, abs_y, w, h);
    }
}

fn resetChildDimensions(box: *box_mod.LayoutBox) void {
    box.dimensions.content.x = 0;
    box.dimensions.content.y = 0;
    box.dimensions.content.width = 0;
    box.dimensions.content.height = 0;
    for (box.children.items) |child| {
        resetChildDimensions(child);
    }
}

pub fn layoutInlineBlock(layout_box: *box_mod.LayoutBox, parent_font_size: f32, allocator: std.mem.Allocator) void {
    const available_width = layout_box.dimensions.content.width;
    const anon_abs_x = layout_box.dimensions.content.x;
    const anon_abs_y = layout_box.dimensions.content.y;

    var cursor_x: f32 = 0;
    var cursor_y: f32 = 0;
    var current_line_height: f32 = parent_font_size * 1.2;

    for (layout_box.children.items) |child| {
        resetChildDimensions(child);
    }

    var segments = std.ArrayListUnmanaged(TextSegment){};
    var buf: [16384]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    
    collectTextSegments(layout_box, &segments, fba.allocator());

    var line_start_idx: usize = 0;
    var current_run_idx: usize = 0;

    for (segments.items) |seg| {
        const space_width = text_measure.measureTextWidth(" ", seg.font_size, seg.font_weight);

        if (std.mem.eql(u8, seg.text, "\n")) {
            alignLine(layout_box, line_start_idx, current_run_idx, available_width, cursor_x);
            line_start_idx = current_run_idx;
            
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

            if (cursor_x + word_width > available_width and cursor_x > 0 and seg.white_space != .nowrap and seg.white_space != .pre) {
                alignLine(layout_box, line_start_idx, current_run_idx, available_width, cursor_x);
                line_start_idx = current_run_idx;
                
                cursor_x = 0;
                cursor_y += current_line_height;
                current_line_height = seg.line_height;
            }

            layout_box.text_runs.append(allocator, .{
                .text = word,
                .styled_node = seg.styled_node,
                .x = anon_abs_x + cursor_x,
                .y = anon_abs_y + cursor_y,
                .width = word_width,
            }) catch continue;
            
            expandBoxRect(seg.layout_box, anon_abs_x + cursor_x, anon_abs_y + cursor_y, word_width, seg.line_height);

            current_run_idx += 1;
            cursor_x += word_width;
            first_word = false;
            current_line_height = @max(current_line_height, seg.line_height);
        }
    }
    
    alignLine(layout_box, line_start_idx, current_run_idx, available_width, cursor_x);
    layout_box.dimensions.content.height = cursor_y + current_line_height;
}

fn alignLine(box: *box_mod.LayoutBox, start_idx: usize, end_idx: usize, available_width: f32, line_width: f32) void {
    if (start_idx >= end_idx) return;
    
    var text_align: properties.TextAlign = .left;
     if (box.parent) |p| {
         if (p.styled_node) |sn| {
             text_align = sn.style.text_align;
         }
     }
    
    if (text_align == .left) return;
    
    var offset: f32 = 0;
    if (text_align == .center) {
        offset = @max(0, (available_width - line_width) / 2.0);
    } else if (text_align == .right) {
        offset = @max(0, available_width - line_width);
    }
    
    if (offset > 0) {
        var i: usize = start_idx;
        while (i < end_idx) : (i += 1) {
            box.text_runs.items[i].x += offset;
        }
    }
}
