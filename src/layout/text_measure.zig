const std = @import("std");

pub const MeasureFn = *const fn (text: []const u8, font_size: f32, font_weight: f32) f32;
pub const LineHeightFn = *const fn (font_family: []const u8, font_size: f32, font_weight: f32) f32;

fn fallbackMeasure(text: []const u8, font_size: f32, _: f32) f32 {
    const codepoint_count = std.unicode.utf8CountCodepoints(text) catch text.len;
    const avg_char_width = font_size * 0.5;
    return @as(f32, @floatFromInt(codepoint_count)) * avg_char_width;
}

fn fallbackLineHeight(_: []const u8, _: f32, _: f32) f32 {
    return 1.2;
}

var global_measure_fn: MeasureFn = fallbackMeasure;
var global_line_height_fn: LineHeightFn = fallbackLineHeight;

pub fn setMeasureFn(f: MeasureFn) void {
    global_measure_fn = f;
}

pub fn setLineHeightFn(f: LineHeightFn) void {
    global_line_height_fn = f;
}

pub fn defaultMeasureFn() MeasureFn {
    return fallbackMeasure;
}

pub fn measureTextWidth(text: []const u8, font_size: f32, font_weight: f32) f32 {
    if (text.len == 0) return 0;
    var w = global_measure_fn(text, font_size, font_weight);
    // Approximate bold width expansion since the backend ignores font_weight.
    if (font_weight >= 600) {
        w *= 1.1;
    }
    return w;
}

pub fn getLineHeightRatio(font_family: []const u8, font_size: f32, font_weight: f32) f32 {
    return global_line_height_fn(font_family, font_size, font_weight);
}
