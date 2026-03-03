const std = @import("std");
const LayoutBox = @import("box.zig").LayoutBox;
const block = @import("block.zig");
const flex = @import("flex.zig");
const values = @import("../css/values.zig");

pub const LayoutContext = struct {
    allocator: std.mem.Allocator,
    viewport_width: f32,
    viewport_height: f32,
    root_font_size: f32 = 16.0,
};

pub fn layoutTree(root: *LayoutBox, ctx: LayoutContext) void {
    root.dimensions.content.width = ctx.viewport_width;
    if (root.box_type == .flexNode) {
        flex.layoutFlexBox(root, null, ctx);
    } else {
        block.layoutBlock(root, null, ctx);
    }
}

pub fn resolveLength(length: ?values.Length, containing_size: f32, ctx: LayoutContext) f32 {
    const l = length orelse return 0;
    return switch (l.unit) {
        .px => l.value,
        .em => l.value * ctx.root_font_size, // TODO: Should be element font size, but for now root
        .rem => l.value * ctx.root_font_size,
        .percent => (l.value / 100.0) * containing_size,
        .auto, .none => 0,
        .vw => (l.value / 100.0) * ctx.viewport_width,
        .vh => (l.value / 100.0) * ctx.viewport_height,
    };
}
