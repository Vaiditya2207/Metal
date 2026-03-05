const std = @import("std");

pub const MeasureFn = *const fn (text: []const u8, font_size: f32, font_weight: f32) f32;

const fallback_char_width: f32 = 8.0;

fn fallbackMeasure(text: []const u8, _: f32, _: f32) f32 {
    return @as(f32, @floatFromInt(text.len)) * fallback_char_width;
}

var global_measure_fn: MeasureFn = fallbackMeasure;

pub fn setMeasureFn(f: MeasureFn) void {
    global_measure_fn = f;
}

pub fn defaultMeasureFn() MeasureFn {
    return fallbackMeasure;
}

pub fn measureTextWidth(text: []const u8, font_size: f32, font_weight: f32) f32 {
    if (text.len == 0) return 0;
    return global_measure_fn(text, font_size, font_weight);
}
