const std = @import("std");
const layout = @import("layout.zig");
const LayoutBox = @import("box.zig").LayoutBox;

pub fn calculatePosition(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    const style = if (box.styled_node) |sn| &sn.style else {
        // L-3 FIX: Anonymous blocks must stack below previous siblings.
        // Use cb.y + cb.height (same as styled blocks) so second+ anonymous
        // blocks don't overlap the first.
        if (containing_block) |cb| {
            box.dimensions.content.x = cb.dimensions.content.x;
            box.dimensions.content.y = cb.dimensions.content.y + cb.dimensions.content.height;
        }
        return;
    };

    const cb_width = if (containing_block) |cb| cb.dimensions.content.width else box.dimensions.content.width;
    const is_floated = if (box.styled_node) |sn| sn.style.float != .none else false;

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

        if (ctx.float_ctx) |fc| {
            if (is_floated) {
                const outer_w = box.dimensions.marginBox().width;
                var float_avail = fc.getAvailableWidth(box.dimensions.content.y, box.dimensions.content.height, cb_width, cb.dimensions.content.x);
                var attempts: usize = 0;
                while (outer_w > float_avail.width) {
                    if (float_avail.width >= cb_width) break;
                    box.dimensions.content.y += 1.0;
                    float_avail = fc.getAvailableWidth(box.dimensions.content.y, box.dimensions.content.height, cb_width, cb.dimensions.content.x);
                    attempts += 1;
                    if (attempts > 10000) break;
                }
            }

            const float_narrowing = fc.getAvailableWidth(box.dimensions.content.y, box.dimensions.content.height, cb_width, cb.dimensions.content.x);
            box.dimensions.content.x += float_narrowing.x_offset;
        }
    } else {
        box.dimensions.content.x = box.dimensions.margin.left +
            box.dimensions.border.left +
            box.dimensions.padding.left;

        box.dimensions.content.y = box.dimensions.margin.top +
            box.dimensions.border.top +
            box.dimensions.padding.top;
    }
}
