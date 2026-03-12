const std = @import("std");
const box = @import("box.zig");
const LayoutBox = box.LayoutBox;
const block = @import("block.zig");
const flex = @import("flex.zig");
const values = @import("../css/values.zig");

pub const FloatSide = enum { left, right };

pub const FloatRect = struct {
    rect: box.Rect,
    side: FloatSide,
};

pub const AvailableSpace = struct {
    x_offset: f32,
    width: f32,
};

pub const FloatContext = struct {
    floats: std.ArrayListUnmanaged(FloatRect) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FloatContext {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FloatContext) void {
        self.floats.deinit(self.allocator);
    }

    pub fn addFloat(self: *FloatContext, rect: box.Rect, side: FloatSide) !void {
        try self.floats.append(self.allocator, .{ .rect = rect, .side = side });
    }

    pub fn getAvailableWidth(self: *FloatContext, y: f32, height: f32, container_width: f32, container_x: f32) AvailableSpace {
        var max_left: f32 = container_x;
        var min_right: f32 = container_x + container_width;

        for (self.floats.items) |f| {
            // Check if float overlaps Y range [y, y+height]
            if (f.rect.y < y + height and f.rect.y + f.rect.height > y) {
                if (f.side == .left) {
                    max_left = @max(max_left, f.rect.x + f.rect.width);
                } else {
                    min_right = @min(min_right, f.rect.x);
                }
            }
        }

        return .{ .x_offset = max_left - container_x, .width = @max(0, min_right - max_left) };
    }

    pub fn getClearY(self: *FloatContext, side: @import("../css/properties.zig").Clear) f32 {
        var max_y: f32 = 0;
        for (self.floats.items) |f| {
            const match = switch (side) {
                .left => f.side == .left,
                .right => f.side == .right,
                .both => true,
                .none => false,
            };
            if (match) {
                max_y = @max(max_y, f.rect.y + f.rect.height);
            }
        }
        return max_y;
    }
};

pub const LayoutContext = struct {
    allocator: std.mem.Allocator,
    viewport_width: f32,
    viewport_height: f32,
    root_font_size: f32 = 16.0,
    float_ctx: ?*FloatContext = null,
    /// Non-zero when a parent flex container stretched this box's cross-axis.
    /// Used by layoutFlexBox to propagate stretch to nested flex children.
    forced_cross_size: f32 = 0,
};

pub fn layoutTree(root: *LayoutBox, ctx: LayoutContext) void {
    root.dimensions.content.width = ctx.viewport_width;

    var fc = FloatContext.init(ctx.allocator);
    defer fc.deinit();

    var mutable_ctx = ctx;
    mutable_ctx.float_ctx = &fc;

    if (root.box_type == .flexNode) {
        flex.layoutFlexBox(root, null, mutable_ctx);
    } else if (root.box_type == .tableNode) {
        @import("table.zig").layoutTable(root, null, mutable_ctx);
    } else {
        block.layoutBlock(root, null, mutable_ctx);
    }
}

pub fn resolveLength(length: ?values.Length, containing_size: f32, ctx: LayoutContext, element_font_size: f32) f32 {
    const l = length orelse return 0;
    return switch (l.unit) {
        .px => l.value,
        .em => l.value * element_font_size,
        .rem => l.value * ctx.root_font_size,
        .percent => (l.value / 100.0) * containing_size,
        .auto, .none => 0,
        .vw => (l.value / 100.0) * ctx.viewport_width,
        .vh => (l.value / 100.0) * ctx.viewport_height,
        .calc => (l.value / 100.0) * containing_size + l.calc_offset,
    };
}
