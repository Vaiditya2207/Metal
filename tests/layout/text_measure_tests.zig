const std = @import("std");
const text_measure = @import("../../src/layout/text_measure.zig");

test "empty string returns zero width" {
    const result = text_measure.measureTextWidth("", 16.0);
    try std.testing.expectEqual(@as(f32, 0.0), result);
}

test "fallback returns length times eight" {
    const result = text_measure.measureTextWidth("hello", 16.0);
    try std.testing.expectEqual(@as(f32, 40.0), result);
}

test "fallback single character" {
    const result = text_measure.measureTextWidth("x", 14.0);
    try std.testing.expectEqual(@as(f32, 8.0), result);
}

test "setMeasureFn overrides measurement" {
    const double_width = struct {
        fn measure(text: []const u8, _: f32) f32 {
            return @as(f32, @floatFromInt(text.len)) * 16.0;
        }
    }.measure;

    text_measure.setMeasureFn(double_width);
    defer text_measure.setMeasureFn(text_measure.defaultMeasureFn());

    const result = text_measure.measureTextWidth("ab", 16.0);
    try std.testing.expectEqual(@as(f32, 32.0), result);
}

test "custom measure function receives font size" {
    const size_reporter = struct {
        fn measure(_: []const u8, font_size: f32) f32 {
            return font_size;
        }
    }.measure;

    text_measure.setMeasureFn(size_reporter);
    defer text_measure.setMeasureFn(text_measure.defaultMeasureFn());

    const result = text_measure.measureTextWidth("any", 24.0);
    try std.testing.expectEqual(@as(f32, 24.0), result);
}
