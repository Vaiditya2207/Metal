const std = @import("std");

pub const Unit = enum {
    px,
    em,
    rem,
    percent,
    vw,
    vh,
    auto,
    none,
    calc,
};

pub const Length = struct {
    value: f32,
    unit: Unit,
    calc_offset: f32 = 0,
};

pub const CssColor = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn fromHex(hex: []const u8) ?CssColor {
        if (hex.len == 0) return null;
        var s = hex;
        if (s[0] == '#') s = s[1..];

        if (s.len == 3) {
            const r = std.fmt.parseInt(u8, s[0..1], 16) catch return null;
            const g = std.fmt.parseInt(u8, s[1..2], 16) catch return null;
            const b = std.fmt.parseInt(u8, s[2..3], 16) catch return null;
            return fromRgb(r * 17, g * 17, b * 17);
        } else if (s.len == 6) {
            const r = std.fmt.parseInt(u8, s[0..2], 16) catch return null;
            const g = std.fmt.parseInt(u8, s[2..4], 16) catch return null;
            const b = std.fmt.parseInt(u8, s[4..6], 16) catch return null;
            return fromRgb(r, g, b);
        } else if (s.len == 8) {
            const r = std.fmt.parseInt(u8, s[0..2], 16) catch return null;
            const g = std.fmt.parseInt(u8, s[2..4], 16) catch return null;
            const b = std.fmt.parseInt(u8, s[4..6], 16) catch return null;
            const a = std.fmt.parseInt(u8, s[6..8], 16) catch return null;
            return CssColor{ .r = r, .g = g, .b = b, .a = a };
        }
        return null;
    }

    pub fn fromNamed(name: []const u8) ?CssColor {
        if (std.mem.eql(u8, name, "transparent")) return CssColor{ .r = 0, .g = 0, .b = 0, .a = 0 };
        const ColorMap = std.StaticStringMap(CssColor).initComptime(.{
            .{ "aliceblue", CssColor{ .r = 240, .g = 248, .b = 255, .a = 255 } },
            .{ "antiquewhite", CssColor{ .r = 250, .g = 235, .b = 215, .a = 255 } },
            .{ "aqua", CssColor{ .r = 0, .g = 255, .b = 255, .a = 255 } },
            .{ "aquamarine", CssColor{ .r = 127, .g = 255, .b = 212, .a = 255 } },
            .{ "azure", CssColor{ .r = 240, .g = 255, .b = 255, .a = 255 } },
            .{ "beige", CssColor{ .r = 245, .g = 245, .b = 220, .a = 255 } },
            .{ "bisque", CssColor{ .r = 255, .g = 228, .b = 196, .a = 255 } },
            .{ "black", CssColor{ .r = 0, .g = 0, .b = 0, .a = 255 } },
            .{ "blanchedalmond", CssColor{ .r = 255, .g = 235, .b = 205, .a = 255 } },
            .{ "blue", CssColor{ .r = 0, .g = 0, .b = 255, .a = 255 } },
            .{ "blueviolet", CssColor{ .r = 138, .g = 43, .b = 226, .a = 255 } },
            .{ "brown", CssColor{ .r = 165, .g = 42, .b = 42, .a = 255 } },
            .{ "burlywood", CssColor{ .r = 222, .g = 184, .b = 135, .a = 255 } },
            .{ "cadetblue", CssColor{ .r = 95, .g = 158, .b = 160, .a = 255 } },
            .{ "chartreuse", CssColor{ .r = 127, .g = 255, .b = 0, .a = 255 } },
            .{ "chocolate", CssColor{ .r = 210, .g = 105, .b = 30, .a = 255 } },
            .{ "coral", CssColor{ .r = 255, .g = 127, .b = 80, .a = 255 } },
            .{ "cornflowerblue", CssColor{ .r = 100, .g = 149, .b = 237, .a = 255 } },
            .{ "cornsilk", CssColor{ .r = 255, .g = 248, .b = 220, .a = 255 } },
            .{ "crimson", CssColor{ .r = 220, .g = 20, .b = 60, .a = 255 } },
            .{ "cyan", CssColor{ .r = 0, .g = 255, .b = 255, .a = 255 } },
            .{ "darkblue", CssColor{ .r = 0, .g = 0, .b = 139, .a = 255 } },
            .{ "darkcyan", CssColor{ .r = 0, .g = 139, .b = 139, .a = 255 } },
            .{ "darkgoldenrod", CssColor{ .r = 184, .g = 134, .b = 11, .a = 255 } },
            .{ "darkgray", CssColor{ .r = 169, .g = 169, .b = 169, .a = 255 } },
            .{ "darkgreen", CssColor{ .r = 0, .g = 100, .b = 0, .a = 255 } },
            .{ "darkgrey", CssColor{ .r = 169, .g = 169, .b = 169, .a = 255 } },
            .{ "darkkhaki", CssColor{ .r = 189, .g = 183, .b = 107, .a = 255 } },
            .{ "darkmagenta", CssColor{ .r = 139, .g = 0, .b = 139, .a = 255 } },
            .{ "darkolivegreen", CssColor{ .r = 85, .g = 107, .b = 47, .a = 255 } },
            .{ "darkorange", CssColor{ .r = 255, .g = 140, .b = 0, .a = 255 } },
            .{ "darkorchid", CssColor{ .r = 153, .g = 50, .b = 204, .a = 255 } },
            .{ "darkred", CssColor{ .r = 139, .g = 0, .b = 0, .a = 255 } },
            .{ "darksalmon", CssColor{ .r = 233, .g = 150, .b = 122, .a = 255 } },
            .{ "darkseagreen", CssColor{ .r = 143, .g = 188, .b = 143, .a = 255 } },
            .{ "darkslateblue", CssColor{ .r = 72, .g = 61, .b = 139, .a = 255 } },
            .{ "darkslategray", CssColor{ .r = 47, .g = 79, .b = 79, .a = 255 } },
            .{ "darkslategrey", CssColor{ .r = 47, .g = 79, .b = 79, .a = 255 } },
            .{ "darkturquoise", CssColor{ .r = 0, .g = 206, .b = 209, .a = 255 } },
            .{ "darkviolet", CssColor{ .r = 148, .g = 0, .b = 211, .a = 255 } },
            .{ "deeppink", CssColor{ .r = 255, .g = 20, .b = 147, .a = 255 } },
            .{ "deepskyblue", CssColor{ .r = 0, .g = 191, .b = 255, .a = 255 } },
            .{ "dimgray", CssColor{ .r = 105, .g = 105, .b = 105, .a = 255 } },
            .{ "dimgrey", CssColor{ .r = 105, .g = 105, .b = 105, .a = 255 } },
            .{ "dodgerblue", CssColor{ .r = 30, .g = 144, .b = 255, .a = 255 } },
            .{ "firebrick", CssColor{ .r = 178, .g = 34, .b = 34, .a = 255 } },
            .{ "floralwhite", CssColor{ .r = 255, .g = 250, .b = 240, .a = 255 } },
            .{ "forestgreen", CssColor{ .r = 34, .g = 139, .b = 34, .a = 255 } },
            .{ "fuchsia", CssColor{ .r = 255, .g = 0, .b = 255, .a = 255 } },
            .{ "gainsboro", CssColor{ .r = 220, .g = 220, .b = 220, .a = 255 } },
            .{ "ghostwhite", CssColor{ .r = 248, .g = 248, .b = 255, .a = 255 } },
            .{ "gold", CssColor{ .r = 255, .g = 215, .b = 0, .a = 255 } },
            .{ "goldenrod", CssColor{ .r = 218, .g = 165, .b = 32, .a = 255 } },
            .{ "gray", CssColor{ .r = 128, .g = 128, .b = 128, .a = 255 } },
            .{ "green", CssColor{ .r = 0, .g = 128, .b = 0, .a = 255 } },
            .{ "greenyellow", CssColor{ .r = 173, .g = 255, .b = 47, .a = 255 } },
            .{ "grey", CssColor{ .r = 128, .g = 128, .b = 128, .a = 255 } },
            .{ "honeydew", CssColor{ .r = 240, .g = 255, .b = 240, .a = 255 } },
            .{ "hotpink", CssColor{ .r = 255, .g = 105, .b = 180, .a = 255 } },
            .{ "indianred", CssColor{ .r = 205, .g = 92, .b = 92, .a = 255 } },
            .{ "indigo", CssColor{ .r = 75, .g = 0, .b = 130, .a = 255 } },
            .{ "ivory", CssColor{ .r = 255, .g = 255, .b = 240, .a = 255 } },
            .{ "khaki", CssColor{ .r = 240, .g = 230, .b = 140, .a = 255 } },
            .{ "lavender", CssColor{ .r = 230, .g = 230, .b = 250, .a = 255 } },
            .{ "lavenderblush", CssColor{ .r = 255, .g = 240, .b = 245, .a = 255 } },
            .{ "lawngreen", CssColor{ .r = 124, .g = 252, .b = 0, .a = 255 } },
            .{ "lemonchiffon", CssColor{ .r = 255, .g = 250, .b = 205, .a = 255 } },
            .{ "lightblue", CssColor{ .r = 173, .g = 216, .b = 230, .a = 255 } },
            .{ "lightcoral", CssColor{ .r = 240, .g = 128, .b = 128, .a = 255 } },
            .{ "lightcyan", CssColor{ .r = 224, .g = 255, .b = 255, .a = 255 } },
            .{ "lightgoldenrodyellow", CssColor{ .r = 250, .g = 250, .b = 210, .a = 255 } },
            .{ "lightgray", CssColor{ .r = 211, .g = 211, .b = 211, .a = 255 } },
            .{ "lightgreen", CssColor{ .r = 144, .g = 238, .b = 144, .a = 255 } },
            .{ "lightgrey", CssColor{ .r = 211, .g = 211, .b = 211, .a = 255 } },
            .{ "lightpink", CssColor{ .r = 255, .g = 182, .b = 193, .a = 255 } },
            .{ "lightsalmon", CssColor{ .r = 255, .g = 160, .b = 122, .a = 255 } },
            .{ "lightseagreen", CssColor{ .r = 32, .g = 178, .b = 170, .a = 255 } },
            .{ "lightskyblue", CssColor{ .r = 135, .g = 206, .b = 250, .a = 255 } },
            .{ "lightslategray", CssColor{ .r = 119, .g = 136, .b = 153, .a = 255 } },
            .{ "lightslategrey", CssColor{ .r = 119, .g = 136, .b = 153, .a = 255 } },
            .{ "lightsteelblue", CssColor{ .r = 176, .g = 196, .b = 222, .a = 255 } },
            .{ "lightyellow", CssColor{ .r = 255, .g = 255, .b = 224, .a = 255 } },
            .{ "lime", CssColor{ .r = 0, .g = 255, .b = 0, .a = 255 } },
            .{ "limegreen", CssColor{ .r = 50, .g = 205, .b = 50, .a = 255 } },
            .{ "linen", CssColor{ .r = 250, .g = 240, .b = 230, .a = 255 } },
            .{ "magenta", CssColor{ .r = 255, .g = 0, .b = 255, .a = 255 } },
            .{ "maroon", CssColor{ .r = 128, .g = 0, .b = 0, .a = 255 } },
            .{ "mediumaquamarine", CssColor{ .r = 102, .g = 205, .b = 170, .a = 255 } },
            .{ "mediumblue", CssColor{ .r = 0, .g = 0, .b = 205, .a = 255 } },
            .{ "mediumorchid", CssColor{ .r = 186, .g = 85, .b = 211, .a = 255 } },
            .{ "mediumpurple", CssColor{ .r = 147, .g = 112, .b = 219, .a = 255 } },
            .{ "mediumseagreen", CssColor{ .r = 60, .g = 179, .b = 113, .a = 255 } },
            .{ "mediumslateblue", CssColor{ .r = 123, .g = 104, .b = 238, .a = 255 } },
            .{ "mediumspringgreen", CssColor{ .r = 0, .g = 250, .b = 154, .a = 255 } },
            .{ "mediumturquoise", CssColor{ .r = 72, .g = 209, .b = 204, .a = 255 } },
            .{ "mediumvioletred", CssColor{ .r = 199, .g = 21, .b = 133, .a = 255 } },
            .{ "midnightblue", CssColor{ .r = 25, .g = 25, .b = 112, .a = 255 } },
            .{ "mintcream", CssColor{ .r = 245, .g = 255, .b = 250, .a = 255 } },
            .{ "mistyrose", CssColor{ .r = 255, .g = 228, .b = 225, .a = 255 } },
            .{ "moccasin", CssColor{ .r = 255, .g = 228, .b = 181, .a = 255 } },
            .{ "navajowhite", CssColor{ .r = 255, .g = 222, .b = 173, .a = 255 } },
            .{ "navy", CssColor{ .r = 0, .g = 0, .b = 128, .a = 255 } },
            .{ "oldlace", CssColor{ .r = 253, .g = 245, .b = 230, .a = 255 } },
            .{ "olive", CssColor{ .r = 128, .g = 128, .b = 0, .a = 255 } },
            .{ "olivedrab", CssColor{ .r = 107, .g = 142, .b = 35, .a = 255 } },
            .{ "orange", CssColor{ .r = 255, .g = 165, .b = 0, .a = 255 } },
            .{ "orangered", CssColor{ .r = 255, .g = 69, .b = 0, .a = 255 } },
            .{ "orchid", CssColor{ .r = 218, .g = 112, .b = 214, .a = 255 } },
            .{ "palegoldenrod", CssColor{ .r = 238, .g = 232, .b = 170, .a = 255 } },
            .{ "palegreen", CssColor{ .r = 152, .g = 251, .b = 152, .a = 255 } },
            .{ "paleturquoise", CssColor{ .r = 175, .g = 238, .b = 238, .a = 255 } },
            .{ "palevioletred", CssColor{ .r = 219, .g = 112, .b = 147, .a = 255 } },
            .{ "papayawhip", CssColor{ .r = 255, .g = 239, .b = 213, .a = 255 } },
            .{ "peachpuff", CssColor{ .r = 255, .g = 218, .b = 185, .a = 255 } },
            .{ "peru", CssColor{ .r = 205, .g = 133, .b = 63, .a = 255 } },
            .{ "pink", CssColor{ .r = 255, .g = 192, .b = 203, .a = 255 } },
            .{ "plum", CssColor{ .r = 221, .g = 160, .b = 221, .a = 255 } },
            .{ "powderblue", CssColor{ .r = 176, .g = 224, .b = 230, .a = 255 } },
            .{ "purple", CssColor{ .r = 128, .g = 0, .b = 128, .a = 255 } },
            .{ "rebeccapurple", CssColor{ .r = 102, .g = 51, .b = 153, .a = 255 } },
            .{ "red", CssColor{ .r = 255, .g = 0, .b = 0, .a = 255 } },
            .{ "rosybrown", CssColor{ .r = 188, .g = 143, .b = 143, .a = 255 } },
            .{ "royalblue", CssColor{ .r = 65, .g = 105, .b = 225, .a = 255 } },
            .{ "saddlebrown", CssColor{ .r = 139, .g = 69, .b = 19, .a = 255 } },
            .{ "salmon", CssColor{ .r = 250, .g = 128, .b = 114, .a = 255 } },
            .{ "sandybrown", CssColor{ .r = 244, .g = 164, .b = 96, .a = 255 } },
            .{ "seagreen", CssColor{ .r = 46, .g = 139, .b = 87, .a = 255 } },
            .{ "seashell", CssColor{ .r = 255, .g = 245, .b = 238, .a = 255 } },
            .{ "sienna", CssColor{ .r = 160, .g = 82, .b = 45, .a = 255 } },
            .{ "silver", CssColor{ .r = 192, .g = 192, .b = 192, .a = 255 } },
            .{ "skyblue", CssColor{ .r = 135, .g = 206, .b = 235, .a = 255 } },
            .{ "slateblue", CssColor{ .r = 106, .g = 90, .b = 205, .a = 255 } },
            .{ "slategray", CssColor{ .r = 112, .g = 128, .b = 144, .a = 255 } },
            .{ "slategrey", CssColor{ .r = 112, .g = 128, .b = 144, .a = 255 } },
            .{ "snow", CssColor{ .r = 255, .g = 250, .b = 250, .a = 255 } },
            .{ "springgreen", CssColor{ .r = 0, .g = 255, .b = 127, .a = 255 } },
            .{ "steelblue", CssColor{ .r = 70, .g = 130, .b = 180, .a = 255 } },
            .{ "tan", CssColor{ .r = 210, .g = 180, .b = 140, .a = 255 } },
            .{ "teal", CssColor{ .r = 0, .g = 128, .b = 128, .a = 255 } },
            .{ "thistle", CssColor{ .r = 216, .g = 191, .b = 216, .a = 255 } },
            .{ "tomato", CssColor{ .r = 255, .g = 99, .b = 71, .a = 255 } },
            .{ "turquoise", CssColor{ .r = 64, .g = 224, .b = 208, .a = 255 } },
            .{ "violet", CssColor{ .r = 238, .g = 130, .b = 238, .a = 255 } },
            .{ "wheat", CssColor{ .r = 245, .g = 222, .b = 179, .a = 255 } },
            .{ "white", CssColor{ .r = 255, .g = 255, .b = 255, .a = 255 } },
            .{ "whitesmoke", CssColor{ .r = 245, .g = 245, .b = 245, .a = 255 } },
            .{ "yellow", CssColor{ .r = 255, .g = 255, .b = 0, .a = 255 } },
            .{ "yellowgreen", CssColor{ .r = 154, .g = 205, .b = 50, .a = 255 } },
        });
        return ColorMap.get(name);
    }

    pub fn fromRgb(r: u8, g: u8, b: u8) CssColor {
        return CssColor{ .r = r, .g = g, .b = b, .a = 255 };
    }
};

pub const CssValue = union(enum) {
    keyword: []const u8,
    length: Length,
    color: CssColor,
    number: f32,
    string: []const u8,
    none,
};

pub fn parseLength(value_str: []const u8) ?Length {
    if (std.mem.eql(u8, value_str, "auto")) return Length{ .value = 0, .unit = .auto };
    if (std.mem.eql(u8, value_str, "none")) return Length{ .value = 0, .unit = .none };

    // Handle calc() expressions
    if (value_str.len > 6 and std.mem.startsWith(u8, value_str, "calc(") and value_str[value_str.len - 1] == ')') {
        return parseCalcExpression(value_str[5 .. value_str.len - 1]);
    }

    if (value_str.len > 1 and value_str[value_str.len - 1] == '%') {
        const val = std.fmt.parseFloat(f32, value_str[0 .. value_str.len - 1]) catch return null;
        return Length{ .value = val, .unit = .percent };
    }

    if (value_str.len > 3) {
        const unit_str = value_str[value_str.len - 3 ..];
        const val_str = value_str[0 .. value_str.len - 3];
        // Only proceed if it looks like a 3-char unit we know
        if (std.mem.eql(u8, unit_str, "rem")) {
            const val = std.fmt.parseFloat(f32, val_str) catch null;
            if (val) |v| return Length{ .value = v, .unit = .rem };
        }
    }

    if (value_str.len > 2) {
        const unit_str = value_str[value_str.len - 2 ..];
        const val_str = value_str[0 .. value_str.len - 2];
        const val = std.fmt.parseFloat(f32, val_str) catch {
            // Might be unitless number like "0"
            const fallback = std.fmt.parseFloat(f32, value_str) catch return null;
            if (fallback == 0) return Length{ .value = 0, .unit = .px };
            return null;
        };

        if (std.mem.eql(u8, unit_str, "px")) return Length{ .value = val, .unit = .px };
        if (std.mem.eql(u8, unit_str, "em")) return Length{ .value = val, .unit = .em };
        if (std.mem.eql(u8, unit_str, "vh")) return Length{ .value = val, .unit = .vh };
        if (std.mem.eql(u8, unit_str, "vw")) return Length{ .value = val, .unit = .vw };
    }

    const num = std.fmt.parseFloat(f32, value_str) catch return null;
    if (num == 0) return Length{ .value = 0, .unit = .px };
    return null;
}

fn parseCalcExpression(expr: []const u8) ?Length {
    const trimmed = std.mem.trim(u8, expr, " \t\n\r");

    // Look for " + " or " - " operator (with spaces around it per CSS spec)
    // Try subtraction first, then addition
    if (findCalcOperator(trimmed, '-')) |op_idx| {
        const left = std.mem.trim(u8, trimmed[0..op_idx], " \t\n\r");
        const right = std.mem.trim(u8, trimmed[op_idx + 1 ..], " \t\n\r");
        const left_len = parseLength(left) orelse return null;
        const right_len = parseLength(right) orelse return null;
        return combineCalcTerms(left_len, right_len, false);
    }
    if (findCalcOperator(trimmed, '+')) |op_idx| {
        const left = std.mem.trim(u8, trimmed[0..op_idx], " \t\n\r");
        const right = std.mem.trim(u8, trimmed[op_idx + 1 ..], " \t\n\r");
        const left_len = parseLength(left) orelse return null;
        const right_len = parseLength(right) orelse return null;
        return combineCalcTerms(left_len, right_len, true);
    }

    // Single value (no operator)
    return parseLength(trimmed);
}

fn findCalcOperator(expr: []const u8, op: u8) ?usize {
    // CSS calc requires spaces around + and - operators
    // Search for ' + ' or ' - ' pattern
    if (expr.len < 3) return null;
    var i: usize = 1;
    while (i + 1 < expr.len) : (i += 1) {
        if (expr[i] == op and expr[i - 1] == ' ' and expr[i + 1] == ' ') {
            return i;
        }
    }
    return null;
}

fn combineCalcTerms(left: Length, right: Length, is_add: bool) ?Length {
    const sign: f32 = if (is_add) 1.0 else -1.0;

    // percent ± px → calc(percent, px_offset)
    if (left.unit == .percent and right.unit == .px) {
        return Length{ .value = left.value, .unit = .calc, .calc_offset = sign * right.value };
    }
    // px ± percent → calc(percent, px_base)
    if (left.unit == .px and right.unit == .percent) {
        return Length{ .value = sign * right.value, .unit = .calc, .calc_offset = left.value };
    }
    // px ± px → just px
    if (left.unit == .px and right.unit == .px) {
        return Length{ .value = left.value + sign * right.value, .unit = .px };
    }
    // percent ± percent → just percent
    if (left.unit == .percent and right.unit == .percent) {
        return Length{ .value = left.value + sign * right.value, .unit = .percent };
    }
    return null;
}

pub fn parseColor(value_str: []const u8) ?CssColor {
    if (value_str.len > 0 and value_str[0] == '#') {
        return CssColor.fromHex(value_str);
    }
    if (value_str.len > 4) {
        if (std.mem.startsWith(u8, value_str, "rgb(") or std.mem.startsWith(u8, value_str, "rgba(")) {
            return parseRgbFunc(value_str);
        }
        if (std.mem.startsWith(u8, value_str, "hsl(") or std.mem.startsWith(u8, value_str, "hsla(")) {
            return parseHslFunc(value_str);
        }
    }
    if (CssColor.fromHex(value_str)) |c| return c;
    return CssColor.fromNamed(value_str);
}

fn parseRgbFunc(value_str: []const u8) ?CssColor {
    const open = std.mem.indexOf(u8, value_str, "(") orelse return null;
    const close = std.mem.lastIndexOf(u8, value_str, ")") orelse return null;
    if (close <= open + 1) return null;
    const content = value_str[open + 1 .. close];
    var parts: [4][]const u8 = undefined;
    var count: usize = 0;
    var iter = std.mem.tokenizeAny(u8, content, ",");
    while (iter.next()) |part| {
        if (count >= 4) return null;
        parts[count] = std.mem.trim(u8, part, " \t\n\r");
        count += 1;
    }
    if (count < 3 or count > 4) return null;
    const r = std.fmt.parseInt(u8, parts[0], 10) catch return null;
    const g = std.fmt.parseInt(u8, parts[1], 10) catch return null;
    const b = std.fmt.parseInt(u8, parts[2], 10) catch return null;
    var a: u8 = 255;
    if (count == 4) {
        if (std.mem.indexOf(u8, parts[3], ".")) |_| {
            const af = std.fmt.parseFloat(f32, parts[3]) catch return null;
            a = @intFromFloat(@min(255.0, @max(0.0, af * 255.0)));
        } else {
            a = std.fmt.parseInt(u8, parts[3], 10) catch return null;
        }
    }
    return CssColor{ .r = r, .g = g, .b = b, .a = a };
}

fn hslToRgb(h: f32, s: f32, l: f32) [3]u8 {
    const c = (1.0 - @abs(2.0 * l - 1.0)) * s;
    const x = c * (1.0 - @abs(@mod(h / 60.0, 2.0) - 1.0));
    const m = l - c / 2.0;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h >= 0 and h < 60) {
        r = c;
        g = x;
        b = 0;
    } else if (h >= 60 and h < 120) {
        r = x;
        g = c;
        b = 0;
    } else if (h >= 120 and h < 180) {
        r = 0;
        g = c;
        b = x;
    } else if (h >= 180 and h < 240) {
        r = 0;
        g = x;
        b = c;
    } else if (h >= 240 and h < 300) {
        r = x;
        g = 0;
        b = c;
    } else if (h >= 300 and h < 360) {
        r = c;
        g = 0;
        b = x;
    }

    return [3]u8{
        @intFromFloat((r + m) * 255.0),
        @intFromFloat((g + m) * 255.0),
        @intFromFloat((b + m) * 255.0),
    };
}

fn parseHslFunc(value_str: []const u8) ?CssColor {
    const open = std.mem.indexOf(u8, value_str, "(") orelse return null;
    const close = std.mem.lastIndexOf(u8, value_str, ")") orelse return null;
    if (close <= open + 1) return null;
    const content = value_str[open + 1 .. close];

    var parts: [4][]const u8 = undefined;
    var count: usize = 0;

    // Split by comma or space
    var iter = std.mem.tokenizeAny(u8, content, ", \t\n\r");
    while (iter.next()) |part| {
        if (std.mem.eql(u8, part, "/")) continue; // handle space-separated syntax
        if (count >= 4) return null;
        parts[count] = part;
        count += 1;
    }
    if (count < 3 or count > 4) return null;

    // Parse HSL
    // H can be deg, turn, rad, grad, or unitless
    var h_val: f32 = 0;
    if (std.mem.endsWith(u8, parts[0], "deg")) {
        h_val = std.fmt.parseFloat(f32, parts[0][0 .. parts[0].len - 3]) catch return null;
    } else if (std.mem.endsWith(u8, parts[0], "turn")) {
        h_val = (std.fmt.parseFloat(f32, parts[0][0 .. parts[0].len - 4]) catch return null) * 360.0;
    } else {
        h_val = std.fmt.parseFloat(f32, parts[0]) catch return null;
    }
    // wrap h
    h_val = @mod(h_val, 360.0);
    if (h_val < 0) h_val += 360.0;

    // Parse S, L (can be % or number 0-1)
    var s_val: f32 = 0;
    if (std.mem.endsWith(u8, parts[1], "%")) {
        s_val = (std.fmt.parseFloat(f32, parts[1][0 .. parts[1].len - 1]) catch return null) / 100.0;
    } else {
        s_val = std.fmt.parseFloat(f32, parts[1]) catch return null;
    }

    var l_val: f32 = 0;
    if (std.mem.endsWith(u8, parts[2], "%")) {
        l_val = (std.fmt.parseFloat(f32, parts[2][0 .. parts[2].len - 1]) catch return null) / 100.0;
    } else {
        l_val = std.fmt.parseFloat(f32, parts[2]) catch return null;
    }
    s_val = std.math.clamp(s_val, 0.0, 1.0);
    l_val = std.math.clamp(l_val, 0.0, 1.0);

    const rgb = hslToRgb(h_val, s_val, l_val);

    var a: u8 = 255;
    if (count == 4) {
        if (std.mem.endsWith(u8, parts[3], "%")) {
            const af = (std.fmt.parseFloat(f32, parts[3][0 .. parts[3].len - 1]) catch return null) / 100.0;
            a = @intFromFloat(std.math.clamp(af, 0.0, 1.0) * 255.0);
        } else if (std.mem.indexOf(u8, parts[3], ".")) |_| {
            const af = std.fmt.parseFloat(f32, parts[3]) catch return null;
            a = @intFromFloat(std.math.clamp(af, 0.0, 1.0) * 255.0);
        } else {
            const af = std.fmt.parseFloat(f32, parts[3]) catch return null;
            if (af <= 1.0 and af >= 0.0) {
                a = @intFromFloat(std.math.clamp(af, 0.0, 1.0) * 255.0);
            } else {
                a = std.fmt.parseInt(u8, parts[3], 10) catch return null;
            }
        }
    }
    return CssColor{ .r = rgb[0], .g = rgb[1], .b = rgb[2], .a = a };
}
