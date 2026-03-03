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
            if (style.top) |t| {
                box.dimensions.content.y += layout.resolveLength(t, ctx.viewport_height, ctx);
            } else if (style.bottom) |b| {
                box.dimensions.content.y -= layout.resolveLength(b, ctx.viewport_height, ctx);
            }

            if (style.left_pos) |l| {
                box.dimensions.content.x += layout.resolveLength(l, ctx.viewport_width, ctx);
            } else if (style.right_pos) |r| {
                box.dimensions.content.x -= layout.resolveLength(r, ctx.viewport_width, ctx);
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
                box.dimensions.content.y = cb_rect.y + layout.resolveLength(t, cb_rect.height, ctx) + box.dimensions.margin.top + box.dimensions.border.top + box.dimensions.padding.top;
            } else if (style.bottom) |b| {
                box.dimensions.content.y = cb_rect.y + cb_rect.height - layout.resolveLength(b, cb_rect.height, ctx) - box.dimensions.content.height - box.dimensions.margin.bottom - box.dimensions.border.bottom - box.dimensions.padding.bottom;
            }

            if (style.left_pos) |l| {
                box.dimensions.content.x = cb_rect.x + layout.resolveLength(l, cb_rect.width, ctx) + box.dimensions.margin.left + box.dimensions.border.left + box.dimensions.padding.left;
            } else if (style.right_pos) |r| {
                box.dimensions.content.x = cb_rect.x + cb_rect.width - layout.resolveLength(r, cb_rect.width, ctx) - box.dimensions.content.width - box.dimensions.margin.right - box.dimensions.border.right - box.dimensions.padding.right;
            }
        },
        .fixed => {
            if (style.top) |t| {
                box.dimensions.content.y = layout.resolveLength(t, ctx.viewport_height, ctx) + box.dimensions.margin.top + box.dimensions.border.top + box.dimensions.padding.top;
            }
            if (style.left_pos) |l| {
                box.dimensions.content.x = layout.resolveLength(l, ctx.viewport_width, ctx) + box.dimensions.margin.left + box.dimensions.border.left + box.dimensions.padding.left;
            }
        },
    }
}
