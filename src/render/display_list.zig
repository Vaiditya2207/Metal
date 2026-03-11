const std = @import("std");
const layout_box = @import("../layout/box.zig");
const properties = @import("../css/properties.zig");
const values = @import("../css/values.zig");

pub const DisplayCommand = union(enum) {
    draw_rect: struct {
        rect: layout_box.Rect,
        color: values.CssColor,
        fixed_to_viewport: bool = false,
        sticky_top: ?f32 = null,
        sticky_bottom: ?f32 = null,
        sticky_left: ?f32 = null,
        sticky_right: ?f32 = null,
    },
    draw_text: struct {
        text: []const u8,
        rect: layout_box.Rect,
        color: values.CssColor,
        font_size: f32,
        font_weight: f32 = 400,
        font_style: properties.FontStyle = .normal,
        fixed_to_viewport: bool = false,
        sticky_top: ?f32 = null,
        sticky_bottom: ?f32 = null,
        sticky_left: ?f32 = null,
        sticky_right: ?f32 = null,
    },
    draw_image: struct {
        rect: layout_box.Rect,
        texture: *anyopaque,
        fixed_to_viewport: bool = false,
        sticky_top: ?f32 = null,
        sticky_bottom: ?f32 = null,
        sticky_left: ?f32 = null,
        sticky_right: ?f32 = null,
    },
    draw_svg: struct {
        rect: layout_box.Rect,
        xml: []const u8,
        fixed_to_viewport: bool = false,
        sticky_top: ?f32 = null,
        sticky_bottom: ?f32 = null,
        sticky_left: ?f32 = null,
        sticky_right: ?f32 = null,
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
        const alloc = self.allocator;
        for (self.commands.items) |cmd| {
            switch (cmd) {
                .draw_text => |t| alloc.free(t.text),
                else => {},
            }
        }
        self.commands.deinit(alloc);
    }
};

pub fn buildDisplayList(allocator: std.mem.Allocator, root: *layout_box.LayoutBox, focused_node: ?*const @import("../dom/node.zig").Node) !DisplayList {
    var dl = DisplayList{
        .commands = .empty,
        .allocator = allocator,
    };
    try walkLayoutTree(&dl, root, focused_node, false, .{});
    return dl;
}

const StickyState = struct {
    top: ?f32 = null,
    bottom: ?f32 = null,
    left: ?f32 = null,
    right: ?f32 = null,
};

fn resolveLengthDummy(l: values.Length, cont: f32, fs: f32) f32 {
    return switch (l.unit) {
        .px => l.value,
        .em => l.value * fs,
        .percent => (l.value / 100.0) * cont,
        else => l.value,
    };
}

fn walkLayoutTree(
    dl: *DisplayList,
    box: *const layout_box.LayoutBox,
    focused_node: ?*const @import("../dom/node.zig").Node,
    is_fixed: bool,
    sticky: StickyState,
) !void {
    var current_fixed = is_fixed;
    var current_sticky = sticky;

    if (box.styled_node) |sn| {
        if (sn.style.position == .fixed) {
            std.debug.print("DisplayList: Found fixed box\n", .{});
            current_fixed = true;
            current_sticky = .{};
        } else if (sn.style.position == .sticky) {
            std.debug.print("DisplayList: Found sticky box: top={any}, bottom={any}\n", .{ sn.style.top, sn.style.bottom });
            const v_w: f32 = 1280.0;
            const v_h: f32 = 800.0;
            const fs = sn.style.font_size.value;
            if (sn.style.top) |t| current_sticky.top = resolveLengthDummy(t, v_h, fs);
            if (sn.style.bottom) |b| current_sticky.bottom = resolveLengthDummy(b, v_h, fs);
            if (sn.style.left_pos) |l| current_sticky.left = resolveLengthDummy(l, v_w, fs);
            if (sn.style.right_pos) |r| current_sticky.right = resolveLengthDummy(r, v_w, fs);
        }
    }

    const box_visible = if (box.styled_node) |sn| sn.style.visibility != .hidden else true;

    // 1. Draw background
    if (box.text_runs.items.len > 0) {
        std.debug.print("DisplayList: Processing {d} text runs, visible={any}\n", .{ box.text_runs.items.len, box_visible });
        for (box.text_runs.items) |run| {
            std.debug.print("  Run at ({d}, {d}) size {d}x{d} '{s}'\n", .{ run.x, run.y, run.width, run.line_height, run.text[0..@min(run.text.len, 10)] });
        }
    }
    if (box.styled_node) |sn| {
        if (box_visible) {
            const opacity = sn.style.opacity;
            const bg_color = sn.style.background_color;
            if (bg_color.a > 0 and box.dimensions.borderBox().width > 0 and box.dimensions.borderBox().height > 0) {
                var color = bg_color;
                if (opacity < 1.0) {
                    color.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * opacity);
                }
                try dl.commands.append(dl.allocator, .{
                    .draw_rect = .{
                        .rect = box.dimensions.borderBox(),
                        .color = color,
                        .fixed_to_viewport = current_fixed,
                        .sticky_top = current_sticky.top,
                        .sticky_bottom = current_sticky.bottom,
                        .sticky_left = current_sticky.left,
                        .sticky_right = current_sticky.right,
                    },
                });
            }

            if (box.background_texture) |tex| {
                const bg_rect = box.dimensions.borderBox();
                if (bg_rect.width > 0 and bg_rect.height > 0) {
                    var tile_w = bg_rect.width;
                    var tile_h = bg_rect.height;
                    const intrinsic_w = box.background_intrinsic_width;
                    const intrinsic_h = box.background_intrinsic_height;

                    if (intrinsic_w > 0 and intrinsic_h > 0) {
                        switch (sn.style.background_size) {
                            .auto => {
                                tile_w = intrinsic_w;
                                tile_h = intrinsic_h;
                            },
                            .contain => {
                                const sx = bg_rect.width / intrinsic_w;
                                const sy = bg_rect.height / intrinsic_h;
                                const s = @min(sx, sy);
                                tile_w = intrinsic_w * s;
                                tile_h = intrinsic_h * s;
                            },
                            .cover => {
                                const sx = bg_rect.width / intrinsic_w;
                                const sy = bg_rect.height / intrinsic_h;
                                const s = @max(sx, sy);
                                tile_w = intrinsic_w * s;
                                tile_h = intrinsic_h * s;
                            },
                        }
                    }

                    tile_w = @max(1.0, tile_w);
                    tile_h = @max(1.0, tile_h);
                    const right = bg_rect.x + bg_rect.width;
                    const bottom = bg_rect.y + bg_rect.height;
                    const max_tiles: usize = 512;

                    switch (sn.style.background_repeat) {
                        .no_repeat => {
                            try dl.commands.append(dl.allocator, .{
                                .draw_image = .{
                                    .rect = .{
                                        .x = bg_rect.x,
                                        .y = bg_rect.y,
                                        .width = @min(tile_w, bg_rect.width),
                                        .height = @min(tile_h, bg_rect.height),
                                    },
                                    .texture = tex,
                                    .fixed_to_viewport = current_fixed,
                                    .sticky_top = current_sticky.top,
                                    .sticky_bottom = current_sticky.bottom,
                                    .sticky_left = current_sticky.left,
                                    .sticky_right = current_sticky.right,
                                },
                            });
                        },
                        .repeat_x => {
                            var x = bg_rect.x;
                            var count: usize = 0;
                            while (x < right and count < max_tiles) : (count += 1) {
                                const w = @min(tile_w, right - x);
                                try dl.commands.append(dl.allocator, .{
                                    .draw_image = .{
                                        .rect = .{
                                            .x = x,
                                            .y = bg_rect.y,
                                            .width = w,
                                            .height = @min(tile_h, bg_rect.height),
                                        },
                                        .texture = tex,
                                        .fixed_to_viewport = current_fixed,
                                        .sticky_top = current_sticky.top,
                                        .sticky_bottom = current_sticky.bottom,
                                        .sticky_left = current_sticky.left,
                                        .sticky_right = current_sticky.right,
                                    },
                                });
                                x += tile_w;
                            }
                        },
                        .repeat_y => {
                            var y = bg_rect.y;
                            var count: usize = 0;
                            while (y < bottom and count < max_tiles) : (count += 1) {
                                const h = @min(tile_h, bottom - y);
                                try dl.commands.append(dl.allocator, .{
                                    .draw_image = .{
                                        .rect = .{
                                            .x = bg_rect.x,
                                            .y = y,
                                            .width = @min(tile_w, bg_rect.width),
                                            .height = h,
                                        },
                                        .texture = tex,
                                        .fixed_to_viewport = current_fixed,
                                        .sticky_top = current_sticky.top,
                                        .sticky_bottom = current_sticky.bottom,
                                        .sticky_left = current_sticky.left,
                                        .sticky_right = current_sticky.right,
                                    },
                                });
                                y += tile_h;
                            }
                        },
                        .repeat => {
                            var y = bg_rect.y;
                            var rows: usize = 0;
                            while (y < bottom and rows < max_tiles) : (rows += 1) {
                                const h = @min(tile_h, bottom - y);
                                var x = bg_rect.x;
                                var cols: usize = 0;
                                while (x < right and cols < max_tiles) : (cols += 1) {
                                    const w = @min(tile_w, right - x);
                                    try dl.commands.append(dl.allocator, .{
                                        .draw_image = .{
                                            .rect = .{
                                                .x = x,
                                                .y = y,
                                                .width = w,
                                                .height = h,
                                            },
                                            .texture = tex,
                                            .fixed_to_viewport = current_fixed,
                                            .sticky_top = current_sticky.top,
                                            .sticky_bottom = current_sticky.bottom,
                                            .sticky_left = current_sticky.left,
                                            .sticky_right = current_sticky.right,
                                        },
                                    });
                                    x += tile_w;
                                }
                                y += tile_h;
                            }
                        },
                    }
                }
            }
        }

        // 2. Draw border (simplified)
        if (box_visible and sn.style.border_width.value > 0 and sn.style.border_color.a > 0) {
            const bw = sn.style.border_width.value;
            const b_box = box.dimensions.borderBox();
            var bc = sn.style.border_color;
            const opacity = sn.style.opacity;
            if (opacity < 1.0) {
                bc.a = @intFromFloat(@as(f32, @floatFromInt(bc.a)) * opacity);
            }
            if (bw > 0) {
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x, .y = b_box.y, .width = b_box.width, .height = bw }, .color = bc, .fixed_to_viewport = current_fixed, .sticky_top = current_sticky.top, .sticky_bottom = current_sticky.bottom, .sticky_left = current_sticky.left, .sticky_right = current_sticky.right }});
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x, .y = b_box.y + b_box.height - bw, .width = b_box.width, .height = bw }, .color = bc, .fixed_to_viewport = current_fixed, .sticky_top = current_sticky.top, .sticky_bottom = current_sticky.bottom, .sticky_left = current_sticky.left, .sticky_right = current_sticky.right }});
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x, .y = b_box.y, .width = bw, .height = b_box.height }, .color = bc, .fixed_to_viewport = current_fixed, .sticky_top = current_sticky.top, .sticky_bottom = current_sticky.bottom, .sticky_left = current_sticky.left, .sticky_right = current_sticky.right }});
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x + b_box.width - bw, .y = b_box.y, .width = bw, .height = b_box.height }, .color = bc, .fixed_to_viewport = current_fixed, .sticky_top = current_sticky.top, .sticky_bottom = current_sticky.bottom, .sticky_left = current_sticky.left, .sticky_right = current_sticky.right }});
            }
        }

        // 3. Draw list bullets
        if (box_visible and sn.style.list_style_type == .disc and std.mem.eql(u8, sn.node.tag_name_str orelse "", "li")) {
            const p_box = box.dimensions.paddingBox();
            const bullet_size = sn.style.font_size.value * 0.4;
            const bullet_y = p_box.y + (sn.style.font_size.value * 1.2 - bullet_size) / 2.0;
            const bullet_x = p_box.x - bullet_size - 10.0;
            var c = sn.style.color;
            const opacity = sn.style.opacity;
            if (opacity < 1.0) c.a = @intFromFloat(@as(f32, @floatFromInt(c.a)) * opacity);
            try dl.commands.append(dl.allocator, .{
                 .draw_rect = .{
                     .rect = .{ .x = bullet_x, .y = bullet_y, .width = bullet_size, .height = bullet_size },
                     .color = c,
                     .fixed_to_viewport = current_fixed,
                     .sticky_top = current_sticky.top,
                     .sticky_bottom = current_sticky.bottom,
                     .sticky_left = current_sticky.left,
                     .sticky_right = current_sticky.right,
                 }
            });
        }
    }

    // 4. Draw image/svg
    if (box_visible) {
        if (box.image_texture) |tex| {
            try dl.commands.append(dl.allocator, .{
                .draw_image = .{
                    .rect = box.dimensions.content,
                    .texture = tex,
                    .fixed_to_viewport = current_fixed,
                    .sticky_top = current_sticky.top,
                    .sticky_bottom = current_sticky.bottom,
                    .sticky_left = current_sticky.left,
                    .sticky_right = current_sticky.right,
                },
            });
        }
        if (box.svg_xml) |xml| {
            try dl.commands.append(dl.allocator, .{
                .draw_svg = .{
                    .rect = box.dimensions.content,
                    .xml = xml,
                    .fixed_to_viewport = current_fixed,
                    .sticky_top = current_sticky.top,
                    .sticky_bottom = current_sticky.bottom,
                    .sticky_left = current_sticky.left,
                    .sticky_right = current_sticky.right,
                },
            });
        }
    }

    // 5. Draw input text
    if (box.styled_node) |sn| {
        if (box_visible and sn.node.node_type == .element and (sn.node.tag == .input or sn.node.tag == .textarea)) {
            const val = sn.node.getAttribute("value") orelse sn.node.getAttribute("placeholder") orelse "";
            var c = sn.style.color;
            if (sn.style.opacity < 1.0) c.a = @intFromFloat(@as(f32, @floatFromInt(c.a)) * sn.style.opacity);
            const rect = layout_box.Rect{
                .x = box.dimensions.content.x + 4.0,
                .y = box.dimensions.content.y + 2.0,
                .width = box.dimensions.content.width - 8.0,
                .height = box.dimensions.content.height - 4.0,
            };

            if (val.len > 0) {
                try dl.commands.append(dl.allocator, .{
                    .draw_text = .{
                        .text = try dl.allocator.dupe(u8, val),
                        .rect = rect,
                        .color = c,
                        .font_size = sn.style.font_size.value,
                        .font_weight = sn.style.font_weight,
                        .fixed_to_viewport = current_fixed,
                        .sticky_top = current_sticky.top,
                        .sticky_bottom = current_sticky.bottom,
                        .sticky_left = current_sticky.left,
                        .sticky_right = current_sticky.right,
                    },
                });
            }
        }
    }

    for (box.text_runs.items) |run| {
        if (run.styled_node.style.visibility == .hidden) continue;
        var color = run.styled_node.style.color;
        if (run.styled_node.style.opacity < 1.0) {
            color.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * run.styled_node.style.opacity);
        }
        
        if (run.width > 0) {
            try dl.commands.append(dl.allocator, .{
                .draw_text = .{
                    .text = try dl.allocator.dupe(u8, run.text),
                    .rect = .{
                        .x = run.x,
                        .y = run.y,
                        .width = run.width,
                        .height = run.styled_node.style.font_size.value * 1.2,
                    },
                    .color = color,
                    .font_size = run.styled_node.style.font_size.value,
                    .font_weight = run.styled_node.style.font_weight,
                    .font_style = run.styled_node.style.font_style,
                    .fixed_to_viewport = current_fixed,
                    .sticky_top = current_sticky.top,
                    .sticky_bottom = current_sticky.bottom,
                    .sticky_left = current_sticky.left,
                    .sticky_right = current_sticky.right,
                },
            });
        }
    }

    var clip_emitted = false;
    if (box.styled_node) |sn| {
        if (sn.style.overflow == .hidden or sn.style.overflow == .scroll) {
            try dl.commands.append(dl.allocator, .{ .push_clip = box.dimensions.paddingBox() });
            clip_emitted = true;
        }
    }

    for (box.children.items) |child| {
        try walkLayoutTree(dl, child, focused_node, current_fixed, current_sticky);
    }

    if (clip_emitted) try dl.commands.append(dl.allocator, .pop_clip);
}
