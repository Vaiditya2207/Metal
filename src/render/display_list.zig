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
        font_weight: f32 = 400,
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
            const bw = sn.style.border_width.value;
            const b_box = box.dimensions.borderBox();
            const bc = sn.style.border_color;
            if (bw > 0) {
                // Top
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x, .y = b_box.y, .width = b_box.width, .height = bw }, .color = bc }});
                // Bottom
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x, .y = b_box.y + b_box.height - bw, .width = b_box.width, .height = bw }, .color = bc }});
                // Left
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x, .y = b_box.y, .width = bw, .height = b_box.height }, .color = bc }});
                // Right
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x + b_box.width - bw, .y = b_box.y, .width = bw, .height = b_box.height }, .color = bc }});
            }
        }

        // 3. Draw list bullets
        if (sn.style.list_style_type == .disc and std.mem.eql(u8, sn.node.tag_name_str orelse "", "li")) {
            const p_box = box.dimensions.paddingBox();
            const bullet_size = sn.style.font_size.value * 0.4;
            const bullet_y = p_box.y + (sn.style.font_size.value * 1.2 - bullet_size) / 2.0;
            const bullet_x = p_box.x - bullet_size - 10.0;
            var c = sn.style.color;
            if (opacity < 1.0) c.a = @intFromFloat(@as(f32, @floatFromInt(c.a)) * opacity);
            try dl.commands.append(dl.allocator, .{
                 .draw_rect = .{
                     .rect = .{ .x = bullet_x, .y = bullet_y, .width = bullet_size, .height = bullet_size },
                     .color = c,
                 }
            });
        }
    }

    for (box.text_runs.items) |run| {
        var color = values.CssColor{ .r = 0, .g = 0, .b = 0, .a = 255 };
        var opacity: f32 = 1.0;
        var font_size: f32 = 16.0;
        var font_weight: f32 = 400.0;
        
        {
            const sn = run.styled_node;
            color = sn.style.color;
            opacity = sn.style.opacity;
            font_size = sn.style.font_size.value;
            font_weight = sn.style.font_weight;
            
            if (sn.style.text_decoration == .underline) {
                 var ul_color = color;
                 if (opacity < 1.0) {
                     ul_color.a = @intFromFloat(@as(f32, @floatFromInt(ul_color.a)) * opacity);
                 }
                 try dl.commands.append(dl.allocator, .{
                     .draw_rect = .{
                         .rect = .{
                             .x = run.x,
                             .y = run.y + (sn.style.line_height * font_size) - 2.0,
                             .width = run.width,
                             .height = 1.0,
                         },
                         .color = ul_color,
                     },
                 });
            }
        }
        
        if (opacity < 1.0) {
            color.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * opacity);
        }
        
        try dl.commands.append(dl.allocator, .{
            .draw_text = .{
                .text = run.text,
                .rect = .{
                    .x = run.x,
                    .y = run.y,
                    .width = run.width,
                    .height = font_size * 1.2,
                },
                .color = color,
                .font_size = font_size,
                .font_weight = font_weight,
            },
        });

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
