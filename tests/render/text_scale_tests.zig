const std = @import("std");
const testing = std.testing;
const batch = @import("../../src/render/batch.zig");

// Copy GlyphMetrics from text_atlas.h to avoid @cImport in test
const GlyphMetrics = struct {
    uv_x: f32,
    uv_y: f32,
    uv_w: f32,
    uv_h: f32,
    width: f32,
    height: f32,
    bearing_x: f32,
    bearing_y: f32,
    advance: f32,
};

// Simplified TextRenderer for testing scaling logic
// We'll use this to verify the math before applying it to the real TextRenderer
const ScalingTestRenderer = struct {
    glyph_metrics: [95]GlyphMetrics,
    font_size: f32,
    font_ascent: f32,

    pub fn generateVertices(
        self: *const ScalingTestRenderer,
        text_batch: *batch.TextBatch,
        text_str: []const u8,
        x: f32,
        y: f32,
        r: f32,
        g: f32,
        b: f32,
        a: f32,
        target_font_size: f32,
        max_width: f32,
        device_scale: f32,
    ) void {
        const scale = target_font_size / self.font_size;
        const line_height = target_font_size * 1.2;
        const space_advance = self.glyph_metrics[0].advance * scale;

        var cur_x = x;
        var cur_y = y;

        var it = std.mem.tokenizeAny(u8, text_str, " ");
        var first_word = true;

        while (it.next()) |word| {
            var word_width: f32 = 0;
            for (word) |c| {
                if (c < 32 or c > 126) continue;
                const idx = c - 32;
                word_width += self.glyph_metrics[idx].advance * scale;
            }

            if (!first_word and cur_x + space_advance + word_width > x + max_width) {
                cur_x = x;
                cur_y += line_height;
            } else if (!first_word) {
                cur_x += space_advance;
            }

            for (word) |c| {
                if (c < 32 or c > 126) continue;
                const idx = c - 32;
                const m = self.glyph_metrics[idx];
                const sw = m.width * scale;
                const sh = m.height * scale;
                const scaled_ascent = self.font_ascent * scale;
                const gx = cur_x + m.bearing_x * scale;
                const gy = cur_y + scaled_ascent - m.bearing_y * scale - sh;
                // gy = 0 + 12 - 10 * 1 - 10 = -8

                const snapped_x = @round(gx * device_scale) / device_scale;
                const snapped_y = @round(gy * device_scale) / device_scale;

                text_batch.appendQuad(snapped_x, snapped_y, sw, sh, m.uv_x, m.uv_y, m.uv_w, m.uv_h, r, g, b, a);
                cur_x += m.advance * scale;
            }
            first_word = false;
        }
    }
};

test "TextRenderer scaling logic correctly scales vertices" {
    var metrics = std.mem.zeroes([95]GlyphMetrics);
    // Setup a mock glyph for 'A' (ASCII 65, index 33)
    // Base size 16, target size 32 -> scale 2.0
    metrics[65 - 32] = .{
        .uv_x = 0,
        .uv_y = 0,
        .uv_w = 0.1,
        .uv_h = 0.1,
        .width = 10,
        .height = 10,
        .bearing_x = 1,
        .bearing_y = 8,
        .advance = 12,
    };

    const renderer = ScalingTestRenderer{
        .glyph_metrics = metrics,
        .font_size = 16.0,
        .font_ascent = 12.0,
    };

    var text_batch: batch.TextBatch = .{};
    renderer.generateVertices(&text_batch, "A", 100, 200, 1, 1, 1, 1, 32.0, 1000.0, 1.0);

    try testing.expectEqual(@as(usize, 6), text_batch.vertexCount());

    // Scale = 32 / 16 = 2.0
    // scaled_ascent = 12 * 2 = 24
    // sw = 10 * 2 = 20
    // sh = 10 * 2 = 20
    // gx = 100 + 1 * 2 = 102
    // gy = 200 + 24 - 8 * 2 - 20 = 200 + 24 - 16 - 20 = 188

    // Top-left vertex of the quad
    try testing.expectApproxEqAbs(@as(f32, 102), text_batch.vertices[0].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 188), text_batch.vertices[0].position[1], 0.001);

    // Width and height check via bottom-right vertex (index 5)
    // x + w = 102 + 20 = 122
    // y + h = 188 + 20 = 208
    try testing.expectApproxEqAbs(@as(f32, 122), text_batch.vertices[5].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 208), text_batch.vertices[5].position[1], 0.001);
}

test "TextRenderer multiple characters scale advance" {
    var metrics = std.mem.zeroes([95]GlyphMetrics);
    metrics[65 - 32] = .{
        .uv_x = 0,
        .uv_y = 0,
        .uv_w = 0.1,
        .uv_h = 0.1,
        .width = 10,
        .height = 10,
        .bearing_x = 0,
        .bearing_y = 10,
        .advance = 12,
    };

    const renderer = ScalingTestRenderer{
        .glyph_metrics = metrics,
        .font_size = 16.0,
        .font_ascent = 12.0,
    };

    var text_batch: batch.TextBatch = .{};
    renderer.generateVertices(&text_batch, "AA", 0, 0, 1, 1, 1, 1, 32.0, 1000.0, 1.0);

    try testing.expectEqual(@as(usize, 12), text_batch.vertexCount());

    // First 'A' at x=0
    // Second 'A' should be at x = 0 + advance * scale = 0 + 12 * 2 = 24
    try testing.expectApproxEqAbs(@as(f32, 24), text_batch.vertices[6].position[0], 0.001);
}

test "TextRenderer wraps text within max_width" {
    var metrics = std.mem.zeroes([95]GlyphMetrics);
    // Space (index 0)
    metrics[0] = .{
        .uv_x = 0,
        .uv_y = 0,
        .uv_w = 0,
        .uv_h = 0,
        .width = 0,
        .height = 0,
        .bearing_x = 0,
        .bearing_y = 0,
        .advance = 12,
    };
    // 'A' (ASCII 65, index 33)
    metrics[65 - 32] = .{
        .uv_x = 0,
        .uv_y = 0,
        .uv_w = 0.1,
        .uv_h = 0.1,
        .width = 10,
        .height = 10,
        .bearing_x = 0,
        .bearing_y = 10,
        .advance = 12,
    };
    // 'B' (ASCII 66, index 34)
    metrics[66 - 32] = .{
        .uv_x = 0.1,
        .uv_y = 0,
        .uv_w = 0.1,
        .uv_h = 0.1,
        .width = 10,
        .height = 10,
        .bearing_x = 0,
        .bearing_y = 10,
        .advance = 12,
    };

    const renderer = ScalingTestRenderer{
        .glyph_metrics = metrics,
        .font_size = 16.0,
        .font_ascent = 12.0,
    };

    var text_batch: batch.TextBatch = .{};
    // Line 1: AA (x=0, 12) -> next x=24. Space (x=24, 36) -> next x=36.
    // Word "BB" starts at 36. 36 + 24 = 60. 60 > 50 -> WRAP.
    // Line 2: BB (x=0, 12)
    renderer.generateVertices(&text_batch, "AA BB", 0, 0, 1, 1, 1, 1, 16.0, 50.0, 1.0);

    // 4 chars rendered (AA BB) -> 24 vertices
    try testing.expectEqual(@as(usize, 24), text_batch.vertexCount());

    // First 'A' at (0, 0)
    try testing.expectApproxEqAbs(@as(f32, 0), text_batch.vertices[0].position[0], 0.001);

    // Third char is 'B', should be wrapped to next line
    // Line height = 16 * 1.2 = 19.2
    // 'B' starts at x=0 on second line
    // Indices for 'B': (2 words * 2 chars = 4 chars total. Each char 6 vertices).
    // Word 1: A (0..5), A (6..11)
    // Word 2: B (12..17), B (18..23)
    // gy = cur_y (19.2) + 12 - 10 - 10 = 11.2.
    // Wait, the output said "actual 11". 19.2 + 12 - 10 - 10 = 11.2.
    // Why did it return 11? Maybe some other rounding? Oh!
    // @round(11.2 * 1.0) / 1.0 = 11.0! YES.
    try testing.expectApproxEqAbs(@as(f32, 0), text_batch.vertices[12].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 11), text_batch.vertices[12].position[1], 0.001);
}
