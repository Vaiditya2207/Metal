const std = @import("std");
const layout_box = @import("../layout/box.zig");
const properties = @import("../css/properties.zig");
const values = @import("../css/values.zig");
const text_measure = @import("../layout/text_measure.zig");

/// Resolve line-height ratio (multiplier) handling the -1.0 sentinel for CSS `normal`.
fn resolveLineHeightRatio(style: *const properties.ComputedStyle) f32 {
    if (style.line_height < 0) {
        return text_measure.getLineHeightRatio(
            style.font_family,
            style.font_size.value,
            style.font_weight,
        );
    }
    return style.line_height;
}

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
        font_style: properties.FontStyle = .normal,
        text_owned: bool = false, // R-7 FIX: true when text was allocated and must be freed
    },
    draw_image: struct {
        rect: layout_box.Rect,
        texture: *anyopaque,
    },
    draw_svg: struct {
        rect: layout_box.Rect,
        xml: []const u8,
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
        // R-7 FIX: Free any owned text allocations before releasing the command list.
        for (self.commands.items) |cmd| {
            switch (cmd) {
                .draw_text => |dt| {
                    if (dt.text_owned) {
                        self.allocator.free(dt.text);
                    }
                },
                else => {},
            }
        }
        self.commands.deinit(self.allocator);
    }
};

pub fn buildDisplayList(allocator: std.mem.Allocator, root: *layout_box.LayoutBox, focused_node: ?*const @import("../dom/node.zig").Node) !DisplayList {
    var dl = DisplayList{
        .commands = .empty,
        .allocator = allocator,
    };
    try walkLayoutTree(&dl, root, focused_node);
    return dl;
}

fn walkLayoutTree(dl: *DisplayList, box: *const layout_box.LayoutBox, focused_node: ?*const @import("../dom/node.zig").Node) !void {
    const box_visible = if (box.styled_node) |sn| sn.style.visibility != .hidden else true;

    // 1. Draw background
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
                // Top
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x, .y = b_box.y, .width = b_box.width, .height = bw }, .color = bc } });
                // Bottom
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x, .y = b_box.y + b_box.height - bw, .width = b_box.width, .height = bw }, .color = bc } });
                // Left
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x, .y = b_box.y, .width = bw, .height = b_box.height }, .color = bc } });
                // Right
                try dl.commands.append(dl.allocator, .{ .draw_rect = .{ .rect = .{ .x = b_box.x + b_box.width - bw, .y = b_box.y, .width = bw, .height = b_box.height }, .color = bc } });
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
            try dl.commands.append(dl.allocator, .{ .draw_rect = .{
                .rect = .{ .x = bullet_x, .y = bullet_y, .width = bullet_size, .height = bullet_size },
                .color = c,
            } });
        }
    }

    // 4. Draw image if this box has a loaded texture
    if (box_visible) {
        if (box.image_texture) |tex| {
            try dl.commands.append(dl.allocator, .{
                .draw_image = .{
                    .rect = box.dimensions.content,
                    .texture = tex,
                },
            });
        }
        if (box.svg_xml) |xml| {
            try dl.commands.append(dl.allocator, .{
                .draw_svg = .{
                    .rect = box.dimensions.content,
                    .xml = xml,
                },
            });
        }
    }

    // 5. Draw input text and cursor
    if (box.styled_node) |sn| {
        if (box_visible and sn.node.node_type == .element and (sn.node.tag == .input or sn.node.tag == .textarea)) {
            const val = sn.node.getAttribute("value") orelse sn.node.getAttribute("placeholder") orelse "";

            var c = sn.style.color;
            if (sn.style.opacity < 1.0) c.a = @intFromFloat(@as(f32, @floatFromInt(c.a)) * sn.style.opacity);
            const text_x = switch (sn.style.text_align) {
                .center => blk: {
                    const tw = text_measure.measureTextWidth(val, sn.style.font_size.value, sn.style.font_weight);
                    break :blk box.dimensions.content.x + @max(0, (box.dimensions.content.width - tw) / 2.0);
                },
                .right => blk: {
                    const tw = text_measure.measureTextWidth(val, sn.style.font_size.value, sn.style.font_weight);
                    break :blk box.dimensions.content.x + box.dimensions.content.width - tw - 4.0;
                },
                else => box.dimensions.content.x + 4.0,
            };
            const rect = layout_box.Rect{
                .x = text_x,
                .y = box.dimensions.content.y + 2.0,
                .width = box.dimensions.content.width,
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
                        .text_owned = true,
                    },
                });
            }

            if (focused_node) |f_node| {
                if (f_node == sn.node) {
                    const char_width = sn.style.font_size.value * 0.6; // approx advance
                    const cursor_x = rect.x + @as(f32, @floatFromInt(val.len)) * char_width;
                    try dl.commands.append(dl.allocator, .{
                        .draw_rect = .{
                            .rect = .{
                                .x = cursor_x,
                                .y = rect.y,
                                .width = 2.0,
                                .height = sn.style.font_size.value,
                            },
                            .color = c,
                        },
                    });
                }
            }
        }
    }

    for (box.text_runs.items) |run| {
        if (run.styled_node.style.visibility == .hidden) continue;
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
                            .y = run.y + (resolveLineHeightRatio(&sn.style) * font_size) - 2.0,
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

        if (run.width > 0) {
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
                    .font_style = run.styled_node.style.font_style,
                },
            });
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
        try walkLayoutTree(dl, child, focused_node);
    }

    if (clip_emitted) {
        try dl.commands.append(dl.allocator, .pop_clip);
    }
}
