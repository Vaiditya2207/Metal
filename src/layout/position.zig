const std = @import("std");
const box_mod = @import("box.zig");
const LayoutBox = box_mod.LayoutBox;
const Rect = box_mod.Rect;
const properties = @import("../css/properties.zig");

const layout = @import("layout.zig");

pub fn getAbsoluteContainingBlock(box: *const LayoutBox) ?*const LayoutBox {
    var current = box.parent;
    while (current) |p| {
        if (p.styled_node) |sn| {
            if (sn.style.position != .static_val) {
                return p;
            }
        }
        current = p.parent;
    }
    return null;
}

pub fn applyPositioning(box: *LayoutBox, ctx: layout.LayoutContext) void {
    const style = if (box.styled_node) |sn| &sn.style else return;

    switch (style.position) {
        .static_val => {},
        .relative => {
            // L-5 FIX: Relative positioning percentages resolve against
            // containing block, not viewport. Walk up to find parent dimensions.
            const cb_height = if (box.parent) |p| p.dimensions.content.height else ctx.viewport_height;
            const cb_width = if (box.parent) |p| p.dimensions.content.width else ctx.viewport_width;

            if (style.top) |t| {
                box.dimensions.content.y += layout.resolveLength(t, cb_height, ctx, style.font_size.value);
            } else if (style.bottom) |b| {
                box.dimensions.content.y -= layout.resolveLength(b, cb_height, ctx, style.font_size.value);
            }

            if (style.left_pos) |l| {
                box.dimensions.content.x += layout.resolveLength(l, cb_width, ctx, style.font_size.value);
            } else if (style.right_pos) |r| {
                box.dimensions.content.x -= layout.resolveLength(r, cb_width, ctx, style.font_size.value);
            }
        },
        .absolute => {
            const cb = getAbsoluteContainingBlock(box);
            // If no positioned ancestor, relative to the initial containing block (root)
            const cb_rect: Rect = if (cb) |c| c.dimensions.content else .{
                .x = 0,
                .y = 0,
                .width = ctx.viewport_width,
                .height = ctx.viewport_height,
            };

            if (style.top) |t| {
                box.dimensions.content.y = cb_rect.y + layout.resolveLength(t, cb_rect.height, ctx, style.font_size.value) + box.dimensions.margin.top + box.dimensions.border.top + box.dimensions.padding.top;
            } else if (style.bottom) |b| {
                box.dimensions.content.y = cb_rect.y + cb_rect.height - layout.resolveLength(b, cb_rect.height, ctx, style.font_size.value) - box.dimensions.content.height - box.dimensions.margin.bottom - box.dimensions.border.bottom - box.dimensions.padding.bottom;
            }

            // CSS 2.1 §10.3.7: For abs-pos elements, when both left and right
            // are specified and width is auto, compute width from containing block.
            const has_explicit_width = style.width != null and style.width.?.unit != .auto;
            if (style.left_pos != null and style.right_pos != null and !has_explicit_width) {
                const l_val = layout.resolveLength(style.left_pos.?, cb_rect.width, ctx, style.font_size.value);
                const r_val = layout.resolveLength(style.right_pos.?, cb_rect.width, ctx, style.font_size.value);
                const h_extras = box.dimensions.margin.left + box.dimensions.border.left + box.dimensions.padding.left +
                    box.dimensions.margin.right + box.dimensions.border.right + box.dimensions.padding.right;
                const computed_w = cb_rect.width - l_val - r_val - h_extras;
                if (computed_w > 0) {
                    box.dimensions.content.width = computed_w;
                }
            }

            if (style.left_pos) |l| {
                box.dimensions.content.x = cb_rect.x + layout.resolveLength(l, cb_rect.width, ctx, style.font_size.value) + box.dimensions.margin.left + box.dimensions.border.left + box.dimensions.padding.left;
            } else if (style.right_pos) |r| {
                box.dimensions.content.x = cb_rect.x + cb_rect.width - layout.resolveLength(r, cb_rect.width, ctx, style.font_size.value) - box.dimensions.content.width - box.dimensions.margin.right - box.dimensions.border.right - box.dimensions.padding.right;
            }
        },
        .fixed => {
            if (style.top) |t| {
                box.dimensions.content.y = layout.resolveLength(t, ctx.viewport_height, ctx, style.font_size.value) + box.dimensions.margin.top + box.dimensions.border.top + box.dimensions.padding.top;
            } else if (style.bottom) |b| {
                box.dimensions.content.y = ctx.viewport_height - layout.resolveLength(b, ctx.viewport_height, ctx, style.font_size.value) - box.dimensions.content.height - box.dimensions.margin.bottom - box.dimensions.border.bottom - box.dimensions.padding.bottom;
            }
            if (style.left_pos) |l| {
                box.dimensions.content.x = layout.resolveLength(l, ctx.viewport_width, ctx, style.font_size.value) + box.dimensions.margin.left + box.dimensions.border.left + box.dimensions.padding.left;
            } else if (style.right_pos) |r| {
                box.dimensions.content.x = ctx.viewport_width - layout.resolveLength(r, ctx.viewport_width, ctx, style.font_size.value) - box.dimensions.content.width - box.dimensions.margin.right - box.dimensions.border.right - box.dimensions.padding.right;
            }
        },
    }
}
