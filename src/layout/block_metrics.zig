const std = @import("std");
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

/// Resolve the definite height of a containing block for percentage-height resolution.
/// CSS 2.1 §10.5: percentage heights resolve against the containing block's *specified* height,
/// not its accumulated content height. If the CB has an explicit height, resolve it
/// (recursively if it's a percentage). If the CB has no explicit height, return its
/// current content height (auto → depends on content).
fn resolveDefiniteHeight(cb: *LayoutBox, ctx: layout.LayoutContext) f32 {
    if (cb.styled_node) |cb_sn| {
        // Document node IS the initial containing block → its height is the viewport.
        if (cb_sn.node.node_type == .document) {
            return ctx.viewport_height;
        }
        if (cb_sn.style.height) |h| {
            switch (h.unit) {
                .percent => {
                    // Resolve percentage against the CB's own containing block.
                    // Walk up via the parent pointer in the layout tree.
                    const grandparent_height = if (cb.parent) |gp|
                        resolveDefiniteHeight(gp, ctx)
                    else
                        ctx.viewport_height; // root element → viewport
                    const resolved = (h.value / 100.0) * grandparent_height;
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
                .auto, .none => return cb.dimensions.content.height,
            }
        }
    }
    // No explicit height → use current accumulated content height
    return cb.dimensions.content.height;
}

pub fn calculateHeight(box: *LayoutBox, containing_block: ?*LayoutBox, ctx: layout.LayoutContext) void {
    if (box.styled_node) |sn| {
        const cb_height = if (containing_block) |cb| resolveDefiniteHeight(cb, ctx) else ctx.viewport_height;

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
                // RC-35: Form controls (input/textarea) have intrinsic size but no intrinsic
                // aspect ratio. Only apply aspect-ratio scaling for replaced elements like img/svg.
                const is_form_control = sn.node.tag == .input or sn.node.tag == .textarea;
                if (!is_form_control and box.intrinsic_width > 0 and box.dimensions.content.width > 0) {
                    const ratio = box.intrinsic_height / box.intrinsic_width;
                    box.dimensions.content.height = box.dimensions.content.width * ratio;
                } else {
                    box.dimensions.content.height = box.intrinsic_height;
                }
            }
        }

        if (sn.style.min_height) |mh| {
            // CSS 2.1 §10.7: percentage min-height with indefinite CB height → treated as 0 (no constraint)
            const skip_min = (mh.unit == .percent or mh.unit == .calc) and cb_height == 0;
            if (!skip_min) {
                const min_h = layout.resolveLength(mh, cb_height, ctx, sn.style.font_size.value);
                if (sn.style.box_sizing == .border_box) {
                    const vertical_extras = box.dimensions.padding.top + box.dimensions.padding.bottom +
                        box.dimensions.border.top + box.dimensions.border.bottom;
                    box.dimensions.content.height = @max(box.dimensions.content.height, @max(0, min_h - vertical_extras));
                } else {
                    box.dimensions.content.height = @max(box.dimensions.content.height, min_h);
                }
            }
        }

        if (sn.style.max_height) |mh| {
            // CSS 2.1 §10.7: percentage max-height with indefinite CB height → treated as none
            const skip_max = (mh.unit == .percent or mh.unit == .calc) and cb_height == 0;
            if (!skip_max) {
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
}

// ── Tests ───────────────────────────────────────────────────────────────

const dom = @import("../dom/mod.zig");
const resolver = @import("../css/resolver.zig");
const properties = @import("../css/properties.zig");

test "RC-35: textarea height uses intrinsic_height, not aspect-ratio scaling" {
    const allocator = std.testing.allocator;

    // Create a textarea DOM node
    var node = dom.Node.init(allocator, .element);
    node.tag = .textarea;

    // Create a styled node with no explicit height
    var sn = resolver.StyledNode{
        .node = &node,
        .style = properties.ComputedStyle{},
        .children = &.{},
    };

    // Create a LayoutBox mimicking a textarea
    var box = LayoutBox.init(.blockNode, &sn);
    box.intrinsic_width = 140.0;
    box.intrinsic_height = 19.2;
    box.dimensions.content.width = 574.0; // flex-expanded width

    // calculateHeight should use intrinsic_height directly (19.2), NOT
    // aspect-ratio: 574 * (19.2/140) = 78.7
    calculateHeight(&box, null, .{
        .allocator = allocator,
        .viewport_width = 1200,
        .viewport_height = 800,
    });

    // Textarea height = intrinsic_height (no aspect-ratio scaling)
    try std.testing.expectApproxEqAbs(@as(f32, 19.2), box.dimensions.content.height, 0.01);
}

test "RC-35: SVG height still uses aspect-ratio scaling" {
    const allocator = std.testing.allocator;

    // Create an SVG DOM node
    var node = dom.Node.init(allocator, .element);
    node.tag = .svg;

    var sn = resolver.StyledNode{
        .node = &node,
        .style = properties.ComputedStyle{},
        .children = &.{},
    };

    var box = LayoutBox.init(.blockNode, &sn);
    box.intrinsic_width = 300.0;
    box.intrinsic_height = 150.0;
    box.dimensions.content.width = 600.0;

    calculateHeight(&box, null, .{
        .allocator = allocator,
        .viewport_width = 1200,
        .viewport_height = 800,
    });

    // SVG should use aspect-ratio: 600 * (150/300) = 300.0
    try std.testing.expectApproxEqAbs(@as(f32, 300.0), box.dimensions.content.height, 0.01);
}

test "RC-35: input height uses intrinsic_height, not aspect-ratio scaling" {
    const allocator = std.testing.allocator;

    var node = dom.Node.init(allocator, .element);
    node.tag = .input;

    var sn = resolver.StyledNode{
        .node = &node,
        .style = properties.ComputedStyle{},
        .children = &.{},
    };

    var box = LayoutBox.init(.blockNode, &sn);
    box.intrinsic_width = 140.0;
    box.intrinsic_height = 19.2;
    box.dimensions.content.width = 300.0;

    calculateHeight(&box, null, .{
        .allocator = allocator,
        .viewport_width = 1200,
        .viewport_height = 800,
    });

    // Input height = intrinsic_height (no aspect-ratio scaling)
    try std.testing.expectApproxEqAbs(@as(f32, 19.2), box.dimensions.content.height, 0.01);
}
