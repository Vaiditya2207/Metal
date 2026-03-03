const std = @import("std");
const values_mod = @import("values.zig");
const Length = values_mod.Length;
const CssColor = values_mod.CssColor;

pub const Display = enum { block, inline_val, none, flex };
pub const Position = enum { static_val, relative, absolute, fixed };
pub const Overflow = enum { visible, hidden, scroll, auto_val };
pub const BoxSizing = enum { content_box, border_box };

pub const FlexDirection = enum { row, column };
pub const JustifyContent = enum { flex_start, flex_end, center, space_between };
pub const AlignItems = enum { stretch, flex_start, flex_end, center };

pub const ComputedStyle = struct {
    display: Display = .inline_val,
    position: Position = .static_val,
    overflow: Overflow = .visible,
    box_sizing: BoxSizing = .content_box,
    flex_direction: FlexDirection = .row,
    justify_content: JustifyContent = .flex_start,
    align_items: AlignItems = .stretch,
    flex_grow: f32 = 0.0,
    flex_shrink: f32 = 1.0,
    flex_basis: ?Length = null,
    width: ?Length = null,
    height: ?Length = null,
    min_width: ?Length = null,
    max_width: ?Length = null,
    min_height: ?Length = null,
    max_height: ?Length = null,
    margin_top: Length = .{ .value = 0, .unit = .px },
    margin_right: Length = .{ .value = 0, .unit = .px },
    margin_bottom: Length = .{ .value = 0, .unit = .px },
    margin_left: Length = .{ .value = 0, .unit = .px },
    padding_top: Length = .{ .value = 0, .unit = .px },
    padding_right: Length = .{ .value = 0, .unit = .px },
    padding_bottom: Length = .{ .value = 0, .unit = .px },
    padding_left: Length = .{ .value = 0, .unit = .px },
    border_width: Length = .{ .value = 0, .unit = .px },
    border_color: CssColor = CssColor.fromRgb(0, 0, 0),
    border_radius: Length = .{ .value = 0, .unit = .px },
    color: CssColor = CssColor.fromRgb(0, 0, 0),
    background_color: CssColor = CssColor{ .r = 0, .g = 0, .b = 0, .a = 0 },
    font_size: Length = .{ .value = 16, .unit = .px },
    font_family: []const u8 = "sans-serif",
    font_weight: f32 = 400,
    top: ?Length = null,
    right_pos: ?Length = null,
    bottom: ?Length = null,
    left_pos: ?Length = null,
    z_index: ?i32 = null,
    opacity: f32 = 1.0,

    pub fn applyProperty(self: *ComputedStyle, prop: []const u8, val: []const u8, allocator: std.mem.Allocator) !void {
        if (std.mem.eql(u8, prop, "display")) {
            if (std.mem.eql(u8, val, "block")) self.display = .block;
            if (std.mem.eql(u8, val, "inline")) self.display = .inline_val;
            if (std.mem.eql(u8, val, "none")) self.display = .none;
            if (std.mem.eql(u8, val, "flex")) self.display = .flex;
        } else if (std.mem.eql(u8, prop, "position")) {
            if (std.mem.eql(u8, val, "static")) self.position = .static_val;
            if (std.mem.eql(u8, val, "relative")) self.position = .relative;
            if (std.mem.eql(u8, val, "absolute")) self.position = .absolute;
            if (std.mem.eql(u8, val, "fixed")) self.position = .fixed;
        } else if (std.mem.eql(u8, prop, "overflow")) {
            if (std.mem.eql(u8, val, "visible")) self.overflow = .visible;
            if (std.mem.eql(u8, val, "hidden")) self.overflow = .hidden;
            if (std.mem.eql(u8, val, "scroll")) self.overflow = .scroll;
            if (std.mem.eql(u8, val, "auto")) self.overflow = .auto_val;
        } else if (std.mem.eql(u8, prop, "box-sizing")) {
            if (std.mem.eql(u8, val, "content-box")) self.box_sizing = .content_box;
            if (std.mem.eql(u8, val, "border-box")) self.box_sizing = .border_box;
        } else if (std.mem.eql(u8, prop, "width")) {
            self.width = values_mod.parseLength(val);
        } else if (std.mem.eql(u8, prop, "height")) {
            self.height = values_mod.parseLength(val);
        } else if (std.mem.startsWith(u8, prop, "min-")) {
            if (std.mem.eql(u8, prop, "min-width")) self.min_width = values_mod.parseLength(val);
            if (std.mem.eql(u8, prop, "min-height")) self.min_height = values_mod.parseLength(val);
        } else if (std.mem.startsWith(u8, prop, "max-")) {
            if (std.mem.eql(u8, prop, "max-width")) self.max_width = values_mod.parseLength(val);
            if (std.mem.eql(u8, prop, "max-height")) self.max_height = values_mod.parseLength(val);
        } else if (std.mem.startsWith(u8, prop, "margin-")) {
            if (values_mod.parseLength(val)) |l| {
                if (std.mem.eql(u8, prop, "margin-top")) self.margin_top = l;
                if (std.mem.eql(u8, prop, "margin-right")) self.margin_right = l;
                if (std.mem.eql(u8, prop, "margin-bottom")) self.margin_bottom = l;
                if (std.mem.eql(u8, prop, "margin-left")) self.margin_left = l;
            }
        } else if (std.mem.startsWith(u8, prop, "padding-")) {
            if (values_mod.parseLength(val)) |l| {
                if (std.mem.eql(u8, prop, "padding-top")) self.padding_top = l;
                if (std.mem.eql(u8, prop, "padding-right")) self.padding_right = l;
                if (std.mem.eql(u8, prop, "padding-bottom")) self.padding_bottom = l;
                if (std.mem.eql(u8, prop, "padding-left")) self.padding_left = l;
            }
        } else if (std.mem.eql(u8, prop, "top")) {
            self.top = values_mod.parseLength(val);
        } else if (std.mem.eql(u8, prop, "right")) {
            self.right_pos = values_mod.parseLength(val);
        } else if (std.mem.eql(u8, prop, "bottom")) {
            self.bottom = values_mod.parseLength(val);
        } else if (std.mem.eql(u8, prop, "left")) {
            self.left_pos = values_mod.parseLength(val);
        } else if (std.mem.eql(u8, prop, "z-index")) {
            self.z_index = std.fmt.parseInt(i32, val, 10) catch null;
        } else if (std.mem.startsWith(u8, prop, "border-")) {
            if (std.mem.eql(u8, prop, "border-width")) {
                if (values_mod.parseLength(val)) |l| self.border_width = l;
            } else if (std.mem.eql(u8, prop, "border-color")) {
                if (values_mod.parseColor(val)) |c| self.border_color = c;
            } else if (std.mem.eql(u8, prop, "border-radius")) {
                if (values_mod.parseLength(val)) |l| self.border_radius = l;
            }
        } else if (std.mem.eql(u8, prop, "color")) {
            if (values_mod.parseColor(val)) |c| self.color = c;
        } else if (std.mem.eql(u8, prop, "background-color")) {
            if (values_mod.parseColor(val)) |c| self.background_color = c;
        } else if (std.mem.eql(u8, prop, "margin")) {
            self.applyShorthand(val, true);
        } else if (std.mem.eql(u8, prop, "padding")) {
            self.applyShorthand(val, false);
        } else if (std.mem.eql(u8, prop, "font-size")) {
            if (values_mod.parseLength(val)) |l| self.font_size = l;
        } else if (std.mem.eql(u8, prop, "font-family")) {
            self.font_family = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, prop, "font-weight")) {
            if (std.mem.eql(u8, val, "normal")) self.font_weight = 400 else if (std.mem.eql(u8, val, "bold")) self.font_weight = 700 else {
                self.font_weight = std.fmt.parseFloat(f32, val) catch 400;
            }
        } else if (std.mem.eql(u8, prop, "opacity")) {
            const f = std.fmt.parseFloat(f32, val) catch 1.0;
            self.opacity = std.math.clamp(f, 0.0, 1.0);
        } else if (std.mem.eql(u8, prop, "flex-direction")) {
            if (std.mem.eql(u8, val, "row")) self.flex_direction = .row;
            if (std.mem.eql(u8, val, "column")) self.flex_direction = .column;
        } else if (std.mem.eql(u8, prop, "justify-content")) {
            if (std.mem.eql(u8, val, "flex-start")) self.justify_content = .flex_start;
            if (std.mem.eql(u8, val, "flex-end")) self.justify_content = .flex_end;
            if (std.mem.eql(u8, val, "center")) self.justify_content = .center;
            if (std.mem.eql(u8, val, "space-between")) self.justify_content = .space_between;
        } else if (std.mem.eql(u8, prop, "align-items")) {
            if (std.mem.eql(u8, val, "stretch")) self.align_items = .stretch;
            if (std.mem.eql(u8, val, "flex-start")) self.align_items = .flex_start;
            if (std.mem.eql(u8, val, "flex-end")) self.align_items = .flex_end;
            if (std.mem.eql(u8, val, "center")) self.align_items = .center;
        } else if (std.mem.eql(u8, prop, "flex-grow")) {
            self.flex_grow = std.fmt.parseFloat(f32, val) catch 0.0;
        } else if (std.mem.eql(u8, prop, "flex-shrink")) {
            self.flex_shrink = std.fmt.parseFloat(f32, val) catch 1.0;
        } else if (std.mem.eql(u8, prop, "flex-basis")) {
            self.flex_basis = values_mod.parseLength(val);
        } else if (std.mem.eql(u8, prop, "flex")) {
            self.flex_grow = std.fmt.parseFloat(f32, val) catch 0.0;
            if (self.flex_grow > 0) {
                self.flex_shrink = 1.0;
                self.flex_basis = .{ .value = 0, .unit = .px };
            }
        }
    }

    fn applyShorthand(self: *ComputedStyle, val: []const u8, is_margin: bool) void {
        var iter = std.mem.tokenizeAny(u8, val, " \t\n\r");
        var parts: [4]Length = undefined;
        var count: usize = 0;
        while (iter.next()) |p| {
            if (count < 4) {
                if (values_mod.parseLength(p)) |l| {
                    parts[count] = l;
                    count += 1;
                }
            }
        }
        const top = if (count > 0) parts[0] else return;
        const right = if (count > 1) parts[1] else top;
        const bottom = if (count > 2) parts[2] else top;
        const left = if (count > 3) parts[3] else right;
        if (is_margin) {
            self.margin_top = top;
            self.margin_right = right;
            self.margin_bottom = bottom;
            self.margin_left = left;
        } else {
            self.padding_top = top;
            self.padding_right = right;
            self.padding_bottom = bottom;
            self.padding_left = left;
        }
    }

    pub fn isInherited(p: []const u8) bool {
        const inherited = [_][]const u8{ "color", "font-size", "font-family", "font-weight" };
        for (inherited) |i| if (std.mem.eql(u8, i, p)) return true;
        return false;
    }
};
