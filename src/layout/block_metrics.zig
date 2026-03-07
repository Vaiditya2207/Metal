const LayoutBox = @import("box.zig").LayoutBox;
const layout = @import("layout.zig");

pub fn shiftBoxY(box: *LayoutBox, delta: f32) void {
    box.dimensions.content.y += delta;
    for (box.text_runs.items) |*run| {
        run.y += delta;
    }
    for (box.children.items) |child| {
        shiftBoxY(child, delta);
    }
}

pub fn shiftBoxX(box: *LayoutBox, delta: f32) void {
    box.dimensions.content.x += delta;
    for (box.text_runs.items) |*run| {
        run.x += delta;
    }
    for (box.children.items) |child| {
        shiftBoxX(child, delta);
    }
}

pub fn calculateHeight(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    if (box.styled_node) |sn| {
        const cb_height = if (containing_block) |cb| cb.dimensions.content.height else ctx.viewport_height;

        if (!box.lock_content_height) {
            if (sn.style.height) |h| {
                const height = layout.resolveLength(h, cb_height, ctx, sn.style.font_size.value);

                if (sn.style.box_sizing == .border_box) {
                    const vertical_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                        box.dimensions.border.top + box.dimensions.border.bottom;
                    box.dimensions.content.height = @max(0, height - vertical_extras);
                } else {
                    box.dimensions.content.height = height;
                }
            } else if (box.intrinsic_height > 0) {
                if (box.intrinsic_width > 0 and box.dimensions.content.width > 0) {
                    const ratio = box.intrinsic_height / box.intrinsic_width;
                    box.dimensions.content.height = box.dimensions.content.width * ratio;
                } else {
                    box.dimensions.content.height = box.intrinsic_height;
                }
            }
        }

        if (sn.style.min_height) |mh| {
            const min_h = layout.resolveLength(mh, cb_height, ctx, sn.style.font_size.value);
            if (sn.style.box_sizing == .border_box) {
                const vertical_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                    box.dimensions.border.top + box.dimensions.border.bottom;
                box.dimensions.content.height = @max(box.dimensions.content.height, @max(0, min_h - vertical_extras));
            } else {
                box.dimensions.content.height = @max(box.dimensions.content.height, min_h);
            }
        }

        if (sn.style.max_height) |mh| {
            const max_h = layout.resolveLength(mh, cb_height, ctx, sn.style.font_size.value);
            if (sn.style.box_sizing == .border_box) {
                const vertical_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                    box.dimensions.border.top + box.dimensions.border.bottom;
                box.dimensions.content.height = @min(box.dimensions.content.height, @max(0, max_h - vertical_extras));
            } else {
                box.dimensions.content.height = @min(box.dimensions.content.height, max_h);
            }
        }
    }
}
