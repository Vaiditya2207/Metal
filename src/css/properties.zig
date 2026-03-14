const std = @import("std");
const values_mod = @import("values.zig");
const Length = values_mod.Length;
const CssColor = values_mod.CssColor;

pub const Display = enum { block, inline_val, inline_block, none, flex, table, table_row, table_cell };
pub const Position = enum { static_val, relative, absolute, fixed };
pub const Overflow = enum { visible, hidden, scroll, auto_val };
pub const BoxSizing = enum { content_box, border_box };

pub const FlexDirection = enum { row, column };
pub const FlexWrap = enum { nowrap, wrap };
pub const JustifyContent = enum { flex_start, flex_end, center, space_between, space_around, space_evenly };
pub const AlignItems = enum { stretch, flex_start, flex_end, center };
pub const BackgroundSize = enum { auto, contain, cover };
pub const BackgroundRepeat = enum { repeat, no_repeat, repeat_x, repeat_y };

pub const TextAlign = enum { left, center, right };
pub const TextDecoration = enum { none, underline };
pub const FontStyle = enum { normal, italic };
pub const ListStyleType = enum { disc, circle, square, decimal, none };
pub const WhiteSpace = enum { normal, nowrap, pre };
pub const Visibility = enum { visible, hidden, collapse };
pub const Float = enum { none, left, right };
pub const Clear = enum { none, left, right, both };

pub const ComputedStyle = struct {
    display: Display = .inline_val,
    position: Position = .static_val,
    overflow: Overflow = .visible,
    visibility: Visibility = .visible,
    box_sizing: BoxSizing = .content_box,
    float: Float = .none,
    clear: Clear = .none,
    flex_direction: FlexDirection = .row,
    flex_wrap: FlexWrap = .nowrap,
    justify_content: JustifyContent = .flex_start,
    align_items: AlignItems = .stretch,
    align_self: ?AlignItems = null,
    row_gap: Length = .{ .value = 0, .unit = .px },
    column_gap: Length = .{ .value = 0, .unit = .px },
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
    background_image_url: ?[]const u8 = null,
    background_size: BackgroundSize = .auto,
    background_repeat: BackgroundRepeat = .repeat,
    font_size: Length = .{ .value = 16, .unit = .px },
    font_family: []const u8 = "sans-serif",
    font_weight: f32 = 400,
    font_style: FontStyle = .normal,
    text_align: TextAlign = .left,
    line_height: f32 = 1.2,
    text_decoration: TextDecoration = .none,
    list_style_type: ListStyleType = .disc,
    white_space: WhiteSpace = .normal,
    top: ?Length = null,
    right_pos: ?Length = null,
    bottom: ?Length = null,
    left_pos: ?Length = null,
    z_index: ?i32 = null,
    opacity: f32 = 1.0,
    custom_properties: std.StringArrayHashMapUnmanaged([]const u8) = .empty,

    pub fn deinit(self: *ComputedStyle, allocator: std.mem.Allocator) void {
        var it = self.custom_properties.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.custom_properties.deinit(allocator);
        if (self.background_image_url) |url| {
            allocator.free(url);
            self.background_image_url = null;
        }
        // Note: font_family is usually a literal unless duped in applyProperty
        // We need a way to track if it's duped. For now, we'll assume it's duped if it's not the default.
        if (!std.mem.eql(u8, self.font_family, "sans-serif") and !std.mem.eql(u8, self.font_family, "serif") and !std.mem.eql(u8, self.font_family, "monospace")) {
            // This is a bit risky but we'll try to free it.
            // Better: move font_family to a fixed-size buffer or handle ownership better.
            // allocator.free(self.font_family);
        }
    }

    pub fn applyProperty(self: *ComputedStyle, prop: []const u8, val: []const u8, allocator: std.mem.Allocator) !void {
        if (std.mem.startsWith(u8, prop, "--")) {
            if (self.custom_properties.getPtr(prop)) |old_val| {
                allocator.free(old_val.*);
                old_val.* = try allocator.dupe(u8, val);
            } else {
                try self.custom_properties.put(allocator, try allocator.dupe(u8, prop), try allocator.dupe(u8, val));
            }
            return;
        }
        if (std.mem.eql(u8, prop, "display")) {
            if (std.mem.eql(u8, val, "block")) self.display = .block;
            if (std.mem.eql(u8, val, "inline")) self.display = .inline_val;
            if (std.mem.eql(u8, val, "inline-block")) self.display = .inline_block;
            if (std.mem.eql(u8, val, "none")) self.display = .none;
            if (std.mem.eql(u8, val, "flex")) self.display = .flex;
            if (std.mem.eql(u8, val, "inline-flex")) self.display = .flex;
            if (std.mem.eql(u8, val, "-webkit-box")) self.display = .flex;
            if (std.mem.eql(u8, val, "-webkit-flex")) self.display = .flex;
            if (std.mem.eql(u8, val, "flow-root")) self.display = .block;
            if (std.mem.eql(u8, val, "grid")) self.display = .block;
            if (std.mem.eql(u8, val, "inline-grid")) self.display = .inline_block;
            if (std.mem.eql(u8, val, "contents")) self.display = .inline_val;
            if (std.mem.eql(u8, val, "table")) self.display = .table;
            if (std.mem.eql(u8, val, "table-row")) self.display = .table_row;
            if (std.mem.eql(u8, val, "table-cell")) self.display = .table_cell;
        } else if (std.mem.eql(u8, prop, "position")) {
            if (std.mem.eql(u8, val, "static")) self.position = .static_val;
            if (std.mem.eql(u8, val, "relative")) self.position = .relative;
            if (std.mem.eql(u8, val, "absolute")) self.position = .absolute;
            if (std.mem.eql(u8, val, "fixed")) self.position = .fixed;
        } else if (std.mem.startsWith(u8, prop, "overflow")) {
            if (std.mem.eql(u8, val, "visible")) self.overflow = .visible;
            if (std.mem.eql(u8, val, "hidden")) self.overflow = .hidden;
            if (std.mem.eql(u8, val, "scroll")) self.overflow = .scroll;
            if (std.mem.eql(u8, val, "auto")) self.overflow = .auto_val;
        } else if (std.mem.eql(u8, prop, "visibility")) {
            if (std.mem.eql(u8, val, "visible")) self.visibility = .visible;
            if (std.mem.eql(u8, val, "hidden")) self.visibility = .hidden;
            if (std.mem.eql(u8, val, "collapse")) self.visibility = .collapse;
        } else if (std.mem.eql(u8, prop, "float")) {
            if (std.mem.eql(u8, val, "none")) self.float = .none;
            if (std.mem.eql(u8, val, "left")) self.float = .left;
            if (std.mem.eql(u8, val, "right")) self.float = .right;
        } else if (std.mem.eql(u8, prop, "clear")) {
            if (std.mem.eql(u8, val, "none")) self.clear = .none;
            if (std.mem.eql(u8, val, "left")) self.clear = .left;
            if (std.mem.eql(u8, val, "right")) self.clear = .right;
            if (std.mem.eql(u8, val, "both")) self.clear = .both;
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
        } else if (std.mem.eql(u8, prop, "inset")) {
            self.applyInsetShorthand(val);
        } else if (std.mem.eql(u8, prop, "z-index")) {
            self.z_index = std.fmt.parseInt(i32, val, 10) catch null;
        } else if (std.mem.eql(u8, prop, "opacity")) {
            if (std.fmt.parseFloat(f32, val)) |opacity_val| {
                self.opacity = @max(0.0, @min(1.0, opacity_val));
            } else |_| {}
        } else if (std.mem.startsWith(u8, prop, "border-") and prop.len > 7) {
            if (std.mem.eql(u8, prop, "border-width")) {
                if (values_mod.parseLength(val)) |l| self.border_width = l;
            } else if (std.mem.eql(u8, prop, "border-color")) {
                if (values_mod.parseColor(val)) |c| self.border_color = c;
            } else if (std.mem.eql(u8, prop, "border-radius")) {
                if (values_mod.parseLength(val)) |l| self.border_radius = l;
            }
        } else if (std.mem.eql(u8, prop, "border")) {
            // border shorthand: border-width border-style border-color
            var iter = std.mem.tokenizeAny(u8, val, " \t");
            while (iter.next()) |token| {
                if (values_mod.parseLength(token)) |l| {
                    self.border_width = l;
                } else if (values_mod.parseColor(token)) |c| {
                    self.border_color = c;
                }
            }
        } else if (std.mem.eql(u8, prop, "color")) {
            if (values_mod.parseColor(val)) |c| self.color = c;
        } else if (std.mem.eql(u8, prop, "background-color")) {
            if (values_mod.parseColor(val)) |c| self.background_color = c;
        } else if (std.mem.eql(u8, prop, "background-image")) {
            if (std.mem.eql(u8, val, "none")) {
                if (self.background_image_url) |old| allocator.free(old);
                self.background_image_url = null;
            } else if (parseCssUrl(val)) |url| {
                if (self.background_image_url) |old| allocator.free(old);
                self.background_image_url = try allocator.dupe(u8, url);
            }
        } else if (std.mem.eql(u8, prop, "background-size")) {
            if (std.mem.eql(u8, val, "cover")) {
                self.background_size = .cover;
            } else if (std.mem.eql(u8, val, "contain")) {
                self.background_size = .contain;
            } else {
                self.background_size = .auto;
            }
        } else if (std.mem.eql(u8, prop, "background-repeat")) {
            if (std.mem.eql(u8, val, "no-repeat")) {
                self.background_repeat = .no_repeat;
            } else if (std.mem.eql(u8, val, "repeat-x")) {
                self.background_repeat = .repeat_x;
            } else if (std.mem.eql(u8, val, "repeat-y")) {
                self.background_repeat = .repeat_y;
            } else {
                self.background_repeat = .repeat;
            }
        } else if (std.mem.eql(u8, prop, "background")) {
            // CSS spec: background shorthand resets all sub-properties to initial values first
            self.background_color = CssColor{ .r = 0, .g = 0, .b = 0, .a = 0 }; // transparent
            if (self.background_image_url) |old| allocator.free(old);
            self.background_image_url = null;
            self.background_repeat = .repeat;
            self.background_size = .auto;

            // Handle "none" explicitly
            const trimmed = std.mem.trim(u8, val, " \t");
            if (std.mem.eql(u8, trimmed, "none") or std.mem.eql(u8, trimmed, "transparent")) {
                // Already reset above — nothing more to do
            } else {
                // Try parsing each token as a color
                var iter = std.mem.tokenizeAny(u8, val, " \t");
                while (iter.next()) |token| {
                    if (values_mod.parseColor(token)) |c| {
                        self.background_color = c;
                    }
                }
                if (parseCssUrl(val)) |url| {
                    self.background_image_url = try allocator.dupe(u8, url);
                }
                if (std.mem.indexOf(u8, val, "no-repeat") != null) {
                    self.background_repeat = .no_repeat;
                } else if (std.mem.indexOf(u8, val, "repeat-x") != null) {
                    self.background_repeat = .repeat_x;
                } else if (std.mem.indexOf(u8, val, "repeat-y") != null) {
                    self.background_repeat = .repeat_y;
                } else if (std.mem.indexOf(u8, val, "repeat") != null) {
                    self.background_repeat = .repeat;
                }
                if (std.mem.indexOf(u8, val, "cover") != null) {
                    self.background_size = .cover;
                } else if (std.mem.indexOf(u8, val, "contain") != null) {
                    self.background_size = .contain;
                }
            }
        } else if (std.mem.eql(u8, prop, "margin")) {
            self.applyShorthand(val, true);
        } else if (std.mem.eql(u8, prop, "padding")) {
            self.applyShorthand(val, false);
        } else if (std.mem.eql(u8, prop, "font-size")) {
            if (values_mod.parseLength(val)) |l| self.font_size = l;
        } else if (std.mem.eql(u8, prop, "font-family")) {
            self.font_family = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, prop, "font-style")) {
            if (std.mem.eql(u8, val, "normal")) self.font_style = .normal;
            if (std.mem.eql(u8, val, "italic")) self.font_style = .italic;
        } else if (std.mem.eql(u8, prop, "font")) {
            var iter = std.mem.tokenizeAny(u8, val, " \t");
            while (iter.next()) |token| {
                if (values_mod.parseLength(token)) |l| {
                    self.font_size = l;
                } else if (std.mem.eql(u8, token, "italic")) {
                    self.font_style = .italic;
                } else if (std.mem.eql(u8, token, "bold")) {
                    self.font_weight = 700;
                } else if (!std.mem.eql(u8, token, "normal")) {
                    // Primitive font-family extraction (last token usually)
                    self.font_family = try allocator.dupe(u8, token);
                }
            }
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
        } else if (std.mem.eql(u8, prop, "flex-wrap")) {
            if (std.mem.eql(u8, val, "wrap")) self.flex_wrap = .wrap;
            if (std.mem.eql(u8, val, "nowrap")) self.flex_wrap = .nowrap;
        } else if (std.mem.eql(u8, prop, "row-gap")) {
            if (values_mod.parseLength(val)) |l| self.row_gap = l;
        } else if (std.mem.eql(u8, prop, "column-gap")) {
            if (values_mod.parseLength(val)) |l| self.column_gap = l;
        } else if (std.mem.eql(u8, prop, "gap")) {
            var iter = std.mem.tokenizeAny(u8, val, " \t\n\r");
            if (iter.next()) |first| {
                if (values_mod.parseLength(first)) |row_l| {
                    self.row_gap = row_l;
                    self.column_gap = row_l;
                }
            }
            if (iter.next()) |second| {
                if (values_mod.parseLength(second)) |col_l| {
                    self.column_gap = col_l;
                }
            }
        } else if (std.mem.eql(u8, prop, "justify-content")) {
            if (std.mem.eql(u8, val, "flex-start")) self.justify_content = .flex_start;
            if (std.mem.eql(u8, val, "flex-end")) self.justify_content = .flex_end;
            if (std.mem.eql(u8, val, "center")) self.justify_content = .center;
            if (std.mem.eql(u8, val, "space-between")) self.justify_content = .space_between;
            if (std.mem.eql(u8, val, "space-around")) self.justify_content = .space_around;
            if (std.mem.eql(u8, val, "space-evenly")) self.justify_content = .space_evenly;
        } else if (std.mem.eql(u8, prop, "text-align")) {
            if (std.mem.eql(u8, val, "left")) self.text_align = .left;
            if (std.mem.eql(u8, val, "center")) self.text_align = .center;
            if (std.mem.eql(u8, val, "right")) self.text_align = .right;
            if (std.mem.eql(u8, val, "start")) self.text_align = .left;
            if (std.mem.eql(u8, val, "end")) self.text_align = .right;
        } else if (std.mem.eql(u8, prop, "line-height")) {
            if (std.mem.eql(u8, val, "normal")) {
                self.line_height = 1.2;
            } else if (values_mod.parseLength(val)) |l| {
                switch (l.unit) {
                    .px => {
                        if (self.font_size.value > 0) {
                            self.line_height = l.value / self.font_size.value;
                        }
                    },
                    .percent => self.line_height = l.value / 100.0,
                    .em, .rem => self.line_height = l.value,
                    else => {
                        self.line_height = std.fmt.parseFloat(f32, val) catch self.line_height;
                    },
                }
            } else {
                self.line_height = std.fmt.parseFloat(f32, val) catch self.line_height;
            }
        } else if (std.mem.eql(u8, prop, "text-decoration")) {
            if (std.mem.eql(u8, val, "none")) self.text_decoration = .none;
            if (std.mem.eql(u8, val, "underline")) self.text_decoration = .underline;
        } else if (std.mem.eql(u8, prop, "list-style-type")) {
            if (std.mem.eql(u8, val, "disc")) self.list_style_type = .disc;
            if (std.mem.eql(u8, val, "circle")) self.list_style_type = .circle;
            if (std.mem.eql(u8, val, "square")) self.list_style_type = .square;
            if (std.mem.eql(u8, val, "decimal")) self.list_style_type = .decimal;
            if (std.mem.eql(u8, val, "none")) self.list_style_type = .none;
        } else if (std.mem.eql(u8, prop, "white-space")) {
            if (std.mem.eql(u8, val, "normal")) self.white_space = .normal;
            if (std.mem.eql(u8, val, "nowrap")) self.white_space = .nowrap;
            if (std.mem.eql(u8, val, "pre")) self.white_space = .pre;
            if (std.mem.eql(u8, val, "pre-wrap")) self.white_space = .pre;
            if (std.mem.eql(u8, val, "pre-line")) self.white_space = .normal;
        } else if (std.mem.eql(u8, prop, "align-items")) {
            if (std.mem.eql(u8, val, "stretch")) self.align_items = .stretch;
            if (std.mem.eql(u8, val, "flex-start")) self.align_items = .flex_start;
            if (std.mem.eql(u8, val, "flex-end")) self.align_items = .flex_end;
            if (std.mem.eql(u8, val, "center")) self.align_items = .center;
            if (std.mem.eql(u8, val, "baseline")) self.align_items = .flex_start;
        } else if (std.mem.eql(u8, prop, "align-self")) {
            if (std.mem.eql(u8, val, "auto")) self.align_self = null;
            if (std.mem.eql(u8, val, "stretch")) self.align_self = .stretch;
            if (std.mem.eql(u8, val, "flex-start")) self.align_self = .flex_start;
            if (std.mem.eql(u8, val, "flex-end")) self.align_self = .flex_end;
            if (std.mem.eql(u8, val, "center")) self.align_self = .center;
            if (std.mem.eql(u8, val, "baseline")) self.align_self = .flex_start;
        } else if (std.mem.eql(u8, prop, "flex-grow")) {
            self.flex_grow = std.fmt.parseFloat(f32, val) catch 0.0;
        } else if (std.mem.eql(u8, prop, "flex-shrink")) {
            self.flex_shrink = std.fmt.parseFloat(f32, val) catch 1.0;
        } else if (std.mem.eql(u8, prop, "flex-basis")) {
            self.flex_basis = values_mod.parseLength(val);
        } else if (std.mem.eql(u8, prop, "flex")) {
            // flex shorthand: flex: <grow> [<shrink>] [<basis>]
            // Also handles keywords: flex: none → 0 0 auto; flex: auto → 1 1 auto
            if (std.mem.eql(u8, val, "none")) {
                self.flex_grow = 0;
                self.flex_shrink = 0;
                self.flex_basis = .{ .value = 0, .unit = .auto };
            } else if (std.mem.eql(u8, val, "auto")) {
                self.flex_grow = 1;
                self.flex_shrink = 1;
                self.flex_basis = .{ .value = 0, .unit = .auto };
            } else {
                var iter = std.mem.tokenizeAny(u8, val, " \t");
                var part_idx: usize = 0;
                var found_basis = false;
                while (iter.next()) |part| {
                    if (part_idx == 0) {
                        // First value: try as flex-grow (number), or as flex-basis (length/percentage)
                        if (std.fmt.parseFloat(f32, part)) |grow| {
                            self.flex_grow = grow;
                        } else |_| {
                            // Not a plain number — try as length/percentage (e.g. "100%", "200px")
                            if (values_mod.parseLength(part)) |len| {
                                self.flex_basis = len;
                                self.flex_grow = 1;
                                self.flex_shrink = 1;
                                found_basis = true;
                            } else {
                                self.flex_grow = 0.0;
                            }
                        }
                    } else if (part_idx == 1) {
                        // Second value: could be flex-shrink (number) or flex-basis (with unit/keyword)
                        if (std.fmt.parseFloat(f32, part)) |shrink| {
                            self.flex_shrink = shrink;
                        } else |_| {
                            // Not a plain number — must be flex-basis
                            self.flex_basis = values_mod.parseLength(part);
                            found_basis = true;
                        }
                    } else if (part_idx == 2 and !found_basis) {
                        // Third value is flex-basis
                        self.flex_basis = values_mod.parseLength(part);
                        found_basis = true;
                    }
                    part_idx += 1;
                }
                // Per CSS spec: when flex shorthand has a <number> but no basis,
                // flex-basis defaults to 0 (not auto).
                if (!found_basis and part_idx >= 1) {
                    if (self.flex_grow > 0) {
                        self.flex_shrink = if (part_idx == 1) 1.0 else self.flex_shrink;
                        self.flex_basis = .{ .value = 0, .unit = .px };
                    }
                }
            }
        }
    }

    fn parseCssUrl(val: []const u8) ?[]const u8 {
        const start_idx = std.mem.indexOf(u8, val, "url(") orelse return null;
        var i = start_idx + 4;
        while (i < val.len and (val[i] == ' ' or val[i] == '\t' or val[i] == '\n' or val[i] == '\r')) : (i += 1) {}
        if (i >= val.len) return null;

        const end_idx = std.mem.indexOfPos(u8, val, i, ")") orelse return null;
        if (end_idx <= i) return null;

        var url_slice = std.mem.trim(u8, val[i..end_idx], " \t\n\r");
        if (url_slice.len >= 2) {
            const first = url_slice[0];
            const last = url_slice[url_slice.len - 1];
            if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) {
                url_slice = url_slice[1 .. url_slice.len - 1];
            }
        }
        if (url_slice.len == 0) return null;
        return url_slice;
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

    fn applyInsetShorthand(self: *ComputedStyle, val: []const u8) void {
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
        if (count == 0) return;

        const top = parts[0];
        const right = if (count > 1) parts[1] else top;
        const bottom = if (count > 2) parts[2] else top;
        const left = if (count > 3) parts[3] else right;

        self.top = top;
        self.right_pos = right;
        self.bottom = bottom;
        self.left_pos = left;
    }

    pub fn isInherited(p: []const u8) bool {
        const inherited = [_][]const u8{ "color", "font-size", "font-family", "font-weight", "font-style", "text-align", "line-height", "list-style-type", "white-space", "text-decoration" };
        for (inherited) |i| if (std.mem.eql(u8, i, p)) return true;
        return false;
    }

    /// Copy a single property value from `parent` into `self`.
    /// Used to implement the CSS `inherit` keyword (CSS Cascading §3.1).
    pub fn copyPropertyFromParent(self: *ComputedStyle, prop: []const u8, parent: *const ComputedStyle) void {
        if (std.mem.eql(u8, prop, "width")) {
            self.width = parent.width;
        } else if (std.mem.eql(u8, prop, "height")) {
            self.height = parent.height;
        } else if (std.mem.eql(u8, prop, "min-width")) {
            self.min_width = parent.min_width;
        } else if (std.mem.eql(u8, prop, "min-height")) {
            self.min_height = parent.min_height;
        } else if (std.mem.eql(u8, prop, "max-width")) {
            self.max_width = parent.max_width;
        } else if (std.mem.eql(u8, prop, "max-height")) {
            self.max_height = parent.max_height;
        } else if (std.mem.eql(u8, prop, "display")) {
            self.display = parent.display;
        } else if (std.mem.eql(u8, prop, "position")) {
            self.position = parent.position;
        } else if (std.mem.eql(u8, prop, "overflow") or std.mem.startsWith(u8, prop, "overflow-")) {
            self.overflow = parent.overflow;
        } else if (std.mem.eql(u8, prop, "visibility")) {
            self.visibility = parent.visibility;
        } else if (std.mem.eql(u8, prop, "box-sizing")) {
            self.box_sizing = parent.box_sizing;
        } else if (std.mem.eql(u8, prop, "float")) {
            self.float = parent.float;
        } else if (std.mem.eql(u8, prop, "clear")) {
            self.clear = parent.clear;
        } else if (std.mem.eql(u8, prop, "margin-top")) {
            self.margin_top = parent.margin_top;
        } else if (std.mem.eql(u8, prop, "margin-right")) {
            self.margin_right = parent.margin_right;
        } else if (std.mem.eql(u8, prop, "margin-bottom")) {
            self.margin_bottom = parent.margin_bottom;
        } else if (std.mem.eql(u8, prop, "margin-left")) {
            self.margin_left = parent.margin_left;
        } else if (std.mem.eql(u8, prop, "padding-top")) {
            self.padding_top = parent.padding_top;
        } else if (std.mem.eql(u8, prop, "padding-right")) {
            self.padding_right = parent.padding_right;
        } else if (std.mem.eql(u8, prop, "padding-bottom")) {
            self.padding_bottom = parent.padding_bottom;
        } else if (std.mem.eql(u8, prop, "padding-left")) {
            self.padding_left = parent.padding_left;
        } else if (std.mem.eql(u8, prop, "margin")) {
            self.margin_top = parent.margin_top;
            self.margin_right = parent.margin_right;
            self.margin_bottom = parent.margin_bottom;
            self.margin_left = parent.margin_left;
        } else if (std.mem.eql(u8, prop, "padding")) {
            self.padding_top = parent.padding_top;
            self.padding_right = parent.padding_right;
            self.padding_bottom = parent.padding_bottom;
            self.padding_left = parent.padding_left;
        } else if (std.mem.eql(u8, prop, "border-width")) {
            self.border_width = parent.border_width;
        } else if (std.mem.eql(u8, prop, "border-color")) {
            self.border_color = parent.border_color;
        } else if (std.mem.eql(u8, prop, "border-radius")) {
            self.border_radius = parent.border_radius;
        } else if (std.mem.eql(u8, prop, "color")) {
            self.color = parent.color;
        } else if (std.mem.eql(u8, prop, "background-color")) {
            self.background_color = parent.background_color;
        } else if (std.mem.eql(u8, prop, "font-size")) {
            self.font_size = parent.font_size;
        } else if (std.mem.eql(u8, prop, "font-family")) {
            self.font_family = parent.font_family;
        } else if (std.mem.eql(u8, prop, "font-weight")) {
            self.font_weight = parent.font_weight;
        } else if (std.mem.eql(u8, prop, "font-style")) {
            self.font_style = parent.font_style;
        } else if (std.mem.eql(u8, prop, "text-align")) {
            self.text_align = parent.text_align;
        } else if (std.mem.eql(u8, prop, "line-height")) {
            self.line_height = parent.line_height;
        } else if (std.mem.eql(u8, prop, "text-decoration")) {
            self.text_decoration = parent.text_decoration;
        } else if (std.mem.eql(u8, prop, "opacity")) {
            self.opacity = parent.opacity;
        } else if (std.mem.eql(u8, prop, "flex-direction")) {
            self.flex_direction = parent.flex_direction;
        } else if (std.mem.eql(u8, prop, "flex-wrap")) {
            self.flex_wrap = parent.flex_wrap;
        } else if (std.mem.eql(u8, prop, "flex-grow")) {
            self.flex_grow = parent.flex_grow;
        } else if (std.mem.eql(u8, prop, "flex-shrink")) {
            self.flex_shrink = parent.flex_shrink;
        } else if (std.mem.eql(u8, prop, "flex-basis")) {
            self.flex_basis = parent.flex_basis;
        } else if (std.mem.eql(u8, prop, "justify-content")) {
            self.justify_content = parent.justify_content;
        } else if (std.mem.eql(u8, prop, "align-items")) {
            self.align_items = parent.align_items;
        } else if (std.mem.eql(u8, prop, "align-self")) {
            self.align_self = parent.align_self;
        } else if (std.mem.eql(u8, prop, "top")) {
            self.top = parent.top;
        } else if (std.mem.eql(u8, prop, "right")) {
            self.right_pos = parent.right_pos;
        } else if (std.mem.eql(u8, prop, "bottom")) {
            self.bottom = parent.bottom;
        } else if (std.mem.eql(u8, prop, "left")) {
            self.left_pos = parent.left_pos;
        } else if (std.mem.eql(u8, prop, "z-index")) {
            self.z_index = parent.z_index;
        } else if (std.mem.eql(u8, prop, "white-space")) {
            self.white_space = parent.white_space;
        } else if (std.mem.eql(u8, prop, "list-style-type")) {
            self.list_style_type = parent.list_style_type;
        }
    }
};

// ── Tests ───────────────────────────────────────────────────────────────

test "RC-42: flex shorthand with percentage as sole value" {
    const allocator = std.testing.allocator;

    // flex: 100% → flex-grow:1, flex-shrink:1, flex-basis:100%
    var style1 = ComputedStyle{};
    try style1.applyProperty("flex", "100%", allocator);
    try std.testing.expectEqual(@as(f32, 1.0), style1.flex_grow);
    try std.testing.expectEqual(@as(f32, 1.0), style1.flex_shrink);
    try std.testing.expect(style1.flex_basis != null);
    try std.testing.expectEqual(@as(f32, 100.0), style1.flex_basis.?.value);
    try std.testing.expectEqual(values_mod.Unit.percent, style1.flex_basis.?.unit);

    // flex: 200px → flex-grow:1, flex-shrink:1, flex-basis:200px
    var style2 = ComputedStyle{};
    try style2.applyProperty("flex", "200px", allocator);
    try std.testing.expectEqual(@as(f32, 1.0), style2.flex_grow);
    try std.testing.expectEqual(@as(f32, 1.0), style2.flex_shrink);
    try std.testing.expect(style2.flex_basis != null);
    try std.testing.expectEqual(@as(f32, 200.0), style2.flex_basis.?.value);
    try std.testing.expectEqual(values_mod.Unit.px, style2.flex_basis.?.unit);

    // flex: 2 → flex-grow:2, flex-shrink:1, flex-basis:0px (existing behavior)
    var style3 = ComputedStyle{};
    try style3.applyProperty("flex", "2", allocator);
    try std.testing.expectEqual(@as(f32, 2.0), style3.flex_grow);
    try std.testing.expect(style3.flex_basis != null);
    try std.testing.expectEqual(@as(f32, 0.0), style3.flex_basis.?.value);
    try std.testing.expectEqual(values_mod.Unit.px, style3.flex_basis.?.unit);
}

test "RC-46: copyPropertyFromParent copies width, height, padding, margin" {
    var parent = ComputedStyle{};
    parent.width = .{ .value = 582, .unit = .px };
    parent.height = .{ .value = 200, .unit = .px };
    parent.padding_top = .{ .value = 10, .unit = .px };
    parent.margin_left = .{ .value = 20, .unit = .px };
    parent.opacity = 0.5;

    var child = ComputedStyle{};
    // width should be null by default
    try std.testing.expect(child.width == null);

    // After copying width from parent, child gets 582px
    child.copyPropertyFromParent("width", &parent);
    try std.testing.expect(child.width != null);
    try std.testing.expectEqual(@as(f32, 582.0), child.width.?.value);
    try std.testing.expectEqual(values_mod.Unit.px, child.width.?.unit);

    // Copy height
    child.copyPropertyFromParent("height", &parent);
    try std.testing.expect(child.height != null);
    try std.testing.expectEqual(@as(f32, 200.0), child.height.?.value);

    // Copy padding-top
    child.copyPropertyFromParent("padding-top", &parent);
    try std.testing.expectEqual(@as(f32, 10.0), child.padding_top.value);

    // Copy margin-left
    child.copyPropertyFromParent("margin-left", &parent);
    try std.testing.expectEqual(@as(f32, 20.0), child.margin_left.value);

    // Copy opacity
    child.copyPropertyFromParent("opacity", &parent);
    try std.testing.expectEqual(@as(f32, 0.5), child.opacity);
}

// ── Visual correctness / background shorthand tests ─────────────────────

test "VR-2: background shorthand resets sub-properties" {
    const allocator = std.testing.allocator;
    var style = ComputedStyle{};

    // Set a background color first
    try style.applyProperty("background-color", "#ff0000", allocator);
    try std.testing.expectEqual(@as(u8, 255), style.background_color.r);

    // Now apply background shorthand with just a URL — should reset bg-color to transparent
    try style.applyProperty("background", "url(image.png) no-repeat", allocator);
    defer if (style.background_image_url) |url| allocator.free(url);

    // background-color should be reset to transparent
    try std.testing.expectEqual(@as(u8, 0), style.background_color.a);
    // background-image-url should be set
    try std.testing.expect(style.background_image_url != null);
    // background-repeat should be no-repeat
    try std.testing.expectEqual(BackgroundRepeat.no_repeat, style.background_repeat);
}

test "VR-2: background none resets everything" {
    const allocator = std.testing.allocator;
    var style = ComputedStyle{};

    // Set various background properties
    try style.applyProperty("background-color", "#ff0000", allocator);
    try style.applyProperty("background-repeat", "no-repeat", allocator);

    // Apply background: none — should reset all
    try style.applyProperty("background", "none", allocator);

    try std.testing.expectEqual(@as(u8, 0), style.background_color.a);
    try std.testing.expectEqual(BackgroundRepeat.repeat, style.background_repeat); // reset to default
}

test "VR-2: background shorthand with color preserves it" {
    const allocator = std.testing.allocator;
    var style = ComputedStyle{};

    try style.applyProperty("background", "#00ff00", allocator);

    try std.testing.expectEqual(@as(u8, 0), style.background_color.r);
    try std.testing.expectEqual(@as(u8, 255), style.background_color.g);
    try std.testing.expectEqual(@as(u8, 0), style.background_color.b);
    try std.testing.expectEqual(@as(u8, 255), style.background_color.a);
}
