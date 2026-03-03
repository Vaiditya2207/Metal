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
};

pub const Length = struct {
    value: f32,
    unit: Unit,
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
        if (std.mem.eql(u8, name, "red")) return fromRgb(255, 0, 0);
        if (std.mem.eql(u8, name, "blue")) return fromRgb(0, 0, 255);
        if (std.mem.eql(u8, name, "black")) return fromRgb(0, 0, 0);
        if (std.mem.eql(u8, name, "white")) return fromRgb(255, 255, 255);
        if (std.mem.eql(u8, name, "green")) return fromRgb(0, 128, 0);
        if (std.mem.eql(u8, name, "yellow")) return fromRgb(255, 255, 0);
        if (std.mem.eql(u8, name, "cyan")) return fromRgb(0, 255, 255);
        if (std.mem.eql(u8, name, "magenta")) return fromRgb(255, 0, 255);
        if (std.mem.eql(u8, name, "orange")) return fromRgb(255, 165, 0);
        if (std.mem.eql(u8, name, "gray")) return fromRgb(128, 128, 128);
        if (std.mem.eql(u8, name, "transparent")) return CssColor{ .r = 0, .g = 0, .b = 0, .a = 0 };
        return null;
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

pub fn parseColor(value_str: []const u8) ?CssColor {
    if (value_str.len > 0 and value_str[0] == '#') {
        return CssColor.fromHex(value_str);
    }
    if (value_str.len > 4) {
        if (std.mem.startsWith(u8, value_str, "rgb(") or std.mem.startsWith(u8, value_str, "rgba(")) {
            return parseRgbFunc(value_str);
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
