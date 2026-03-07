const layout = @import("layout.zig");
const LayoutBox = @import("box.zig").LayoutBox;

pub fn calculateWidth(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
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

    const is_floated = if (box.styled_node) |sn| sn.style.float != .none else false;

    if (!box.lock_content_width) {
        if (width) |w| {
            if (style.box_sizing == .border_box) {
                const horizontal_extras = padding_left + padding_right + border_left + border_right;
                box.dimensions.content.width = @max(0, w - horizontal_extras);
            } else {
                box.dimensions.content.width = w;
            }
        } else {
            if (box.intrinsic_width > 0) {
                const horizontal_extras = padding_left + padding_right + border_left + border_right;
                if (style.box_sizing == .border_box) {
                    box.dimensions.content.width = @max(0, box.intrinsic_width - horizontal_extras);
                } else {
                    box.dimensions.content.width = box.intrinsic_width;
                }
            } else {
                box.dimensions.content.width = @max(0, cb_width - total_extras);
            }
        }
    }

    if (ctx.float_ctx) |fc| {
        var presumed_y = if (containing_block) |cb| cb.dimensions.content.y + cb.dimensions.content.height else 0;

        if (is_floated) {
            var float_avail = fc.getAvailableWidth(presumed_y, 10.0, cb_width, if (containing_block) |cb| cb.dimensions.content.x else 0);
            var attempts: usize = 0;
            while (box.dimensions.content.width + padding_left + padding_right + border_left + border_right > float_avail.width) {
                if (float_avail.width >= cb_width) break;
                presumed_y += 1.0;
                float_avail = fc.getAvailableWidth(presumed_y, 10.0, cb_width, if (containing_block) |cb| cb.dimensions.content.x else 0);
                attempts += 1;
                if (attempts > 10000) break;
            }
            const float_narrowing = fc.getAvailableWidth(presumed_y, box.dimensions.content.height, cb_width, if (containing_block) |cb| cb.dimensions.content.x else 0);
            box.dimensions.content.width = @min(box.dimensions.content.width, float_narrowing.width);
        }
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

    const width_is_auto = if (style.width) |w| w.unit == .auto else true;
    if (!width_is_auto) {
        const current_content_width = box.dimensions.content.width;
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
