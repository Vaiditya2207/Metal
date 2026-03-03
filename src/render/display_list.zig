const std = @import("std");
const layout_box = @import("../layout/box.zig");
const properties = @import("../css/properties.zig");
const values = @import("../css/values.zig");

pub const DisplayCommand = union(enum) {
    draw_rect: struct {
        rect: layout_box.Rect,
        color: values.CssColor,
    },
    draw_text: struct {
        text: []const u8,
        rect: layout_box.Rect,
        color: values.CssColor,
        font_size: f32,
    },
    push_clip: layout_box.Rect,
    pop_clip: void,
};

pub const DisplayList = struct {
    commands: std.ArrayListUnmanaged(DisplayCommand),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DisplayList {
        return .{
            .commands = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DisplayList) void {
        self.commands.deinit(self.allocator);
    }
};

pub fn buildDisplayList(allocator: std.mem.Allocator, root_box: *const layout_box.LayoutBox) !DisplayList {
    var dl = DisplayList.init(allocator);
    errdefer dl.deinit();

    try walkLayoutTree(&dl, root_box);

    return dl;
}

fn walkLayoutTree(dl: *DisplayList, box: *const layout_box.LayoutBox) !void {
    // 1. Draw background
    if (box.styled_node) |sn| {
        const opacity = sn.style.opacity;
        const bg_color = sn.style.background_color;
        if (bg_color.a > 0) {
            var color = bg_color;
            if (opacity < 1.0) {
                color.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * opacity);
            }
            try dl.commands.append(dl.allocator, .{
                .draw_rect = .{
                    .rect = box.dimensions.borderBox(),
                    .color = color,
                },
            });
        }

        // 2. Draw border (simplified)
        if (sn.style.border_width.value > 0 and sn.style.border_color.a > 0) {
            // For now just draw the border box with border color
            // In a real renderer we'd draw 4 lines or a hollow rect
        }
    }

    // 3. Draw text (if any)
    if (box.styled_node) |sn| {
        const opacity = sn.style.opacity;
        if (sn.node.node_type == .text) {
            if (sn.node.data) |text| {
                var color = sn.style.color;
                if (opacity < 1.0) {
                    color.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * opacity);
                }
                try dl.commands.append(dl.allocator, .{
                    .draw_text = .{
                        .text = text,
                        .rect = box.dimensions.content,
                        .color = color,
                        .font_size = sn.style.font_size.value,
                    },
                });
            }
        }
    }

    // Clip around children if overflow is hidden/scroll
    var clip_emitted = false;
    if (box.styled_node) |sn| {
        if (sn.style.overflow == .hidden or sn.style.overflow == .scroll) {
            try dl.commands.append(dl.allocator, .{
                .push_clip = box.dimensions.paddingBox(),
            });
            clip_emitted = true;
        }
    }

    // 4. Children (Painter's algorithm: draw children on top)
    for (box.children.items) |child| {
        try walkLayoutTree(dl, child);
    }

    if (clip_emitted) {
        try dl.commands.append(dl.allocator, .pop_clip);
    }
}
