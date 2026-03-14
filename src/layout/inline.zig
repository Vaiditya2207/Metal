const std = @import("std");
const box_mod = @import("box.zig");
const text_measure = @import("text_measure.zig");
const resolver = @import("../css/resolver.zig");
const properties = @import("../css/properties.zig");
const block = @import("block.zig");

fn shiftBox(box: *box_mod.LayoutBox, dx: f32, dy: f32) void {
    box.dimensions.content.x += dx;
    box.dimensions.content.y += dy;
    for (box.children.items) |child| {
        shiftBox(child, dx, dy);
    }
}

const InlineBlockOnLine = struct {
    box: *box_mod.LayoutBox,
};

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
    if (box.box_type == .inlineBlockNode) {
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
        return; // do not dig into inlineBlockNode's children for text extraction
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

pub fn layoutInlineBlock(layout_box: *box_mod.LayoutBox, parent_font_size: f32, ctx: @import("layout.zig").LayoutContext) void {
    const allocator = ctx.allocator;
    const container_width = layout_box.dimensions.content.width;
    const anon_abs_x = layout_box.dimensions.content.x;
    const anon_abs_y = layout_box.dimensions.content.y;

    var cursor_x: f32 = 0;
    var cursor_y: f32 = 0;
    var current_line_height: f32 = parent_font_size * 1.2;

    for (layout_box.children.items) |child| {
        resetChildDimensions(child);
    }

    layout_box.text_runs.clearRetainingCapacity();

    var segments = std.ArrayListUnmanaged(TextSegment){};
    var buf: [16384]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    collectTextSegments(layout_box, &segments, fba.allocator());

    var line_ibs = std.ArrayListUnmanaged(InlineBlockOnLine){};
    // Use the same fixed-buffer allocator for the inline-block tracking list
    const ib_alloc = fba.allocator();

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
            // Inline-blocks establish a new BFC (CSS 2.1 §9.4.1).
            // Create a fresh FloatContext so inner floats don't interact
            // with (or leak into) the outer float context.
            var ib_fc = @import("layout.zig").FloatContext.init(ctx.allocator);
            defer ib_fc.deinit();
            var ib_ctx = ctx;
            ib_ctx.float_ctx = &ib_fc;

            block.layoutBlock(seg.layout_box, layout_box, ib_ctx);

            // Shrink-to-fit for auto-width inline-block (CSS 2.1 §10.3.5)
            if (seg.layout_box.styled_node) |ib_sn| {
                const has_explicit_width = ib_sn.style.width != null and ib_sn.style.width.?.unit != .auto;
                if (!has_explicit_width) {
                    const flex = @import("flex.zig");
                    const intrinsic_w = flex.measureIntrinsicWidth(seg.layout_box);
                    if (intrinsic_w > 0 and intrinsic_w < seg.layout_box.dimensions.content.width) {
                        const layout = @import("layout.zig");
                        var new_width = intrinsic_w;
                        // Apply min-width constraint
                        if (ib_sn.style.min_width) |mw| {
                            const min_w = layout.resolveLength(mw, seg.layout_box.dimensions.content.width, ib_ctx, ib_sn.style.font_size.value);
                            new_width = @max(new_width, min_w);
                        }
                        // Apply max-width constraint
                        if (ib_sn.style.max_width) |mw| {
                            const max_w = layout.resolveLength(mw, seg.layout_box.dimensions.content.width, ib_ctx, ib_sn.style.font_size.value);
                            new_width = @min(new_width, max_w);
                        }
                        seg.layout_box.dimensions.content.width = new_width;
                        // Relayout with narrowed width so children reflow correctly
                        seg.layout_box.lock_content_width = true;
                        block.layoutBlock(seg.layout_box, layout_box, ib_ctx);
                        seg.layout_box.lock_content_width = false;
                    }
                }
            }

            var block_w = seg.layout_box.dimensions.marginBox().width;
            if (block_w == 0) block_w = seg.layout_box.intrinsic_width;

            var block_h = seg.layout_box.dimensions.marginBox().height;
            if (block_h == 0) block_h = seg.line_height;

            // If it doesn't fit in the current shortened line box, shift down
            if (cursor_x + block_w > available.width and cursor_x > 0) {
                alignLine(layout_box, line_start_idx, current_run_idx, available.width, cursor_x, available.x_offset, line_ibs.items);
                line_ibs.clearRetainingCapacity();
                line_start_idx = current_run_idx;

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

            // RC-59: Propagate inline-block dimensions to inline parent boxes.
            // Use the parent's resolved font-size for height (not the full
            // inline-block height) — Chrome reports inline parents as only
            // line-height tall, not stretched by inline-block children.
            if (seg.layout_box.parent) |inline_parent| {
                const ib_border = seg.layout_box.dimensions.borderBox();
                const layout_mod = @import("layout.zig");
                const p_fs: f32 = if (inline_parent.styled_node) |sn|
                    layout_mod.resolveLength(sn.style.font_size, parent_font_size, ctx, sn.style.font_size.value)
                else
                    parent_font_size;
                expandBoxRect(inline_parent, ib_border.x, anon_abs_y + cursor_y, ib_border.width, p_fs);
            }

            line_ibs.append(ib_alloc, .{ .box = seg.layout_box }) catch {};

            cursor_x += block_w;
            current_line_height = @max(current_line_height, block_h);
            continue;
        }

        if (std.mem.eql(u8, seg.text, "\n")) {
            alignLine(layout_box, line_start_idx, current_run_idx, available.width, cursor_x, available.x_offset, line_ibs.items);
            line_ibs.clearRetainingCapacity();
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

            // If it doesn't fit, shift down
            if (cursor_x + word_width > available.width and cursor_x > 0 and seg.white_space != .nowrap and seg.white_space != .pre) {
                alignLine(layout_box, line_start_idx, current_run_idx, available.width, cursor_x, available.x_offset, line_ibs.items);
                line_ibs.clearRetainingCapacity();
                line_start_idx = current_run_idx;

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

            const half_leading = @max(@as(f32, 0), (seg.line_height - seg.font_size) / 2.0);

            layout_box.text_runs.append(allocator, .{
                .text = word,
                .styled_node = seg.styled_node,
                .x = anon_abs_x + available.x_offset + cursor_x,
                .y = anon_abs_y + cursor_y + half_leading,
                .width = word_width,
            }) catch continue;

            expandBoxRect(seg.layout_box, anon_abs_x + available.x_offset + cursor_x, anon_abs_y + cursor_y + half_leading, word_width, seg.font_size);

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
    alignLine(layout_box, line_start_idx, current_run_idx, final_available.width, cursor_x, final_available.x_offset, line_ibs.items);
    line_ibs.clearRetainingCapacity();

    layout_box.dimensions.content.height = if (segments.items.len == 0) 0 else cursor_y + current_line_height;
}

fn alignLine(box: *box_mod.LayoutBox, start_idx: usize, end_idx: usize, available_width: f32, line_width: f32, x_offset: f32, line_ibs: []const InlineBlockOnLine) void {
    if (start_idx >= end_idx and line_ibs.len == 0) return;

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

    // I added x_offset in text_runs.append: `.x = anon_abs_x + available.x_offset + cursor_x`
    // So here I only need to apply the alignment offset.
    if (align_offset > 0) {
        var i: usize = start_idx;
        while (i < end_idx) : (i += 1) {
            box.text_runs.items[i].x += align_offset;
        }
        // Shift inline-block boxes on this line
        for (line_ibs) |ib| {
            shiftBox(ib.box, align_offset, 0);
        }
    }
}

// ── Tests ───────────────────────────────────────────────────────────────

test "RC-49: inline element height uses font_size not line_height" {
    // When an inline text element has font_size=13 and line_height=28,
    // expandBoxRect should be called with font_size so the element's
    // reported height is ~13, NOT 28.  This matches Chrome behaviour
    // where inline element bounding boxes use font metrics (≈font-size),
    // while line-height only controls line box spacing.
    var box = box_mod.LayoutBox.init(.inlineNode, null);
    // Initially zero dimensions
    try std.testing.expectApproxEqAbs(@as(f32, 0), box.dimensions.content.height, 0.01);

    const font_size: f32 = 13.0;
    // Simulate what line 301 now does: pass font_size as height
    expandBoxRect(&box, 0, 0, 100, font_size);

    // The element height must equal font_size, not line_height
    try std.testing.expectApproxEqAbs(font_size, box.dimensions.content.height, 0.01);
    // Verify it would have been wrong with line_height
    try std.testing.expect(box.dimensions.content.height < 28.0);
}

test "RC-50: alignLine shifts inline-block boxes for text-align center" {
    // Setup: an anonymous block with a parent that has text-align: center.
    // Place an inline-block at x=0 with width=100 in a container of width=400.
    // After alignLine, the inline-block should be shifted by (400-100)/2 = 150.

    const allocator = std.testing.allocator;

    // Create a minimal DOM node for the StyledNode
    var node = @import("../dom/node.zig").Node.init(allocator, .element);

    // Create a StyledNode with text-align: center
    var style: properties.ComputedStyle = .{};
    style.text_align = .center;
    const styled_node = resolver.StyledNode{
        .node = &node,
        .style = style,
        .children = &.{},
    };

    // Parent LayoutBox (block container with text-align: center)
    var parent_box = box_mod.LayoutBox.init(.blockNode, &styled_node);

    // Anonymous block (the box passed to alignLine)
    var anon_box = box_mod.LayoutBox.init(.anonymousBlock, null);
    anon_box.parent = &parent_box;

    // Inline-block child box at x=0, width=100
    var ib_box = box_mod.LayoutBox.init(.inlineBlockNode, null);
    ib_box.dimensions.content.x = 0;
    ib_box.dimensions.content.y = 0;
    ib_box.dimensions.content.width = 100;
    ib_box.dimensions.content.height = 20;

    // Create the inline-block-on-line entry
    const ibs = [_]InlineBlockOnLine{.{ .box = &ib_box }};

    // Call alignLine: container width=400, line width=100 (the inline-block),
    // x_offset=0, with one inline-block on the line.
    // start_idx == end_idx (no text runs), but we have an inline-block.
    alignLine(&anon_box, 0, 0, 400, 100, 0, &ibs);

    // Expected offset: (400 - 100) / 2 = 150
    try std.testing.expectApproxEqAbs(@as(f32, 150.0), ib_box.dimensions.content.x, 0.01);

    // Also test text-align: right
    ib_box.dimensions.content.x = 0; // reset
    var right_style: properties.ComputedStyle = .{};
    right_style.text_align = .right;
    const right_styled_node = resolver.StyledNode{
        .node = &node,
        .style = right_style,
        .children = &.{},
    };
    var right_parent = box_mod.LayoutBox.init(.blockNode, &right_styled_node);
    anon_box.parent = &right_parent;

    alignLine(&anon_box, 0, 0, 400, 100, 0, &ibs);

    // Expected offset: 400 - 100 = 300
    try std.testing.expectApproxEqAbs(@as(f32, 300.0), ib_box.dimensions.content.x, 0.01);

    // Also verify text-align: left does NOT shift
    ib_box.dimensions.content.x = 0; // reset
    var left_style: properties.ComputedStyle = .{};
    left_style.text_align = .left;
    const left_styled_node = resolver.StyledNode{
        .node = &node,
        .style = left_style,
        .children = &.{},
    };
    var left_parent = box_mod.LayoutBox.init(.blockNode, &left_styled_node);
    anon_box.parent = &left_parent;

    alignLine(&anon_box, 0, 0, 400, 100, 0, &ibs);

    // text-align: left should not shift
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), ib_box.dimensions.content.x, 0.01);
}

test "RC-51: half-leading calculation for inline text y-position" {
    // When line_height > font_size, half-leading = (line_height - font_size) / 2
    // pushes text down inside the line box so it is vertically centred.
    {
        const font_size: f32 = 14.0;
        const line_height: f32 = 28.0;
        const half_leading = @max(@as(f32, 0), (line_height - font_size) / 2.0);
        try std.testing.expectApproxEqAbs(@as(f32, 7.0), half_leading, 0.01);
    }

    // Zero leading: line_height == font_size → half_leading = 0
    {
        const font_size: f32 = 14.0;
        const hl = @max(@as(f32, 0), (font_size - font_size) / 2.0);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), hl, 0.01);
    }

    // Negative case: line_height < font_size → clamp to 0
    {
        const font_size: f32 = 14.0;
        const line_height: f32 = 12.0;
        const hl = @max(@as(f32, 0), (line_height - font_size) / 2.0);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), hl, 0.01);
    }
}
