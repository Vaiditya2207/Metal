const std = @import("std");
const values = @import("../../src/css/values.zig");

test "css_val:01 color from hex 3-digit" {
    const color = values.CssColor.fromHex("f00").?;
    try std.testing.expectEqual(@as(u8, 255), color.r);
    try std.testing.expectEqual(@as(u8, 0), color.g);
    try std.testing.expectEqual(@as(u8, 0), color.b);
    try std.testing.expectEqual(@as(u8, 255), color.a);
}

test "css_val:02 color from hex 6-digit" {
    const color = values.CssColor.fromHex("00ff00").?;
    try std.testing.expectEqual(@as(u8, 0), color.r);
    try std.testing.expectEqual(@as(u8, 255), color.g);
    try std.testing.expectEqual(@as(u8, 0), color.b);
    try std.testing.expectEqual(@as(u8, 255), color.a);
}

test "css_val:03 color from hex 8-digit" {
    const color = values.CssColor.fromHex("0000ff80").?;
    try std.testing.expectEqual(@as(u8, 0), color.r);
    try std.testing.expectEqual(@as(u8, 0), color.g);
    try std.testing.expectEqual(@as(u8, 255), color.b);
    try std.testing.expectEqual(@as(u8, 128), color.a);
}

test "css_val:04 color from hex invalid" {
    try std.testing.expect(values.CssColor.fromHex("xyz") == null);
    try std.testing.expect(values.CssColor.fromHex("12") == null);
    try std.testing.expect(values.CssColor.fromHex("12345") == null);
}

test "css_val:05 color from named" {
    const red = values.CssColor.fromNamed("red").?;
    try std.testing.expectEqual(@as(u8, 255), red.r);

    const transparent = values.CssColor.fromNamed("transparent").?;
    try std.testing.expectEqual(@as(u8, 0), transparent.a);

    try std.testing.expect(values.CssColor.fromNamed("unknown") == null);
}

test "css_val:06 parse length px" {
    const len = values.parseLength("10px").?;
    try std.testing.expectEqual(@as(f32, 10), len.value);
    try std.testing.expectEqual(values.Unit.px, len.unit);
}

test "css_val:07 parse length em" {
    const len = values.parseLength("2.5em").?;
    try std.testing.expectEqual(@as(f32, 2.5), len.value);
    try std.testing.expectEqual(values.Unit.em, len.unit);
}

test "css_val:08 parse length percent" {
    const len = values.parseLength("50%").?;
    try std.testing.expectEqual(@as(f32, 50), len.value);
    try std.testing.expectEqual(values.Unit.percent, len.unit);
}

test "css_val:09 parse length auto" {
    const len = values.parseLength("auto").?;
    try std.testing.expectEqual(@as(f32, 0), len.value);
    try std.testing.expectEqual(values.Unit.auto, len.unit);
}

test "css_val:10 parse length invalid" {
    try std.testing.expect(values.parseLength("abc") == null);
}

test "css_val:11 parse color hex" {
    const color = values.parseColor("#ff0000").?;
    try std.testing.expectEqual(@as(u8, 255), color.r);
}

test "css_val:12 parse color named" {
    const color = values.parseColor("blue").?;
    try std.testing.expectEqual(@as(u8, 255), color.b);
}

test "css_val:13 css value union" {
    const val = values.CssValue{ .number = 42.0 };
    try std.testing.expectEqual(@as(f32, 42.0), val.number);
}

test "css_val:14 bare zero is valid zero-length" {
    const len = values.parseLength("0").?;
    try std.testing.expectEqual(@as(f32, 0), len.value);
    try std.testing.expectEqual(values.Unit.px, len.unit);
}

test "css_val:15 bare nonzero is null" {
    try std.testing.expect(values.parseLength("10") == null);
}

test "css_val:16 rgb function" {
    const color = values.parseColor("rgb(255, 0, 0)").?;
    try std.testing.expectEqual(@as(u8, 255), color.r);
    try std.testing.expectEqual(@as(u8, 0), color.g);
    try std.testing.expectEqual(@as(u8, 0), color.b);
    try std.testing.expectEqual(@as(u8, 255), color.a);
}

test "css_val:17 rgba function" {
    const color = values.parseColor("rgba(0, 128, 255, 0.5)").?;
    try std.testing.expectEqual(@as(u8, 0), color.r);
    try std.testing.expectEqual(@as(u8, 128), color.g);
    try std.testing.expectEqual(@as(u8, 255), color.b);
    // 0.5 * 255 = 127.5, @intFromFloat might be 127 or 128 depending on rounding
    try std.testing.expect(color.a == 127 or color.a == 128);
}

test "css_val:18 rgba with integer alpha" {
    const color = values.parseColor("rgba(255, 255, 255, 128)").?;
    try std.testing.expectEqual(@as(u8, 128), color.a);
}
