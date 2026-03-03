const std = @import("std");
const app = @import("../platform/app.zig");
const objc = app.objc;
const batch_mod = @import("batch.zig");

pub const TextRenderer = struct {
    atlas_texture: *anyopaque,
    text_pipeline: *anyopaque,
    glyph_metrics: [95]objc.GlyphMetrics,
    font_size: f32,
    font_ascent: f32,

    pub fn init(device: *anyopaque, font_size: f32) !TextRenderer {
        var metrics: [95]objc.GlyphMetrics = undefined;
        var ascent: f32 = 0;
        const texture = objc.create_font_atlas(device, font_size, @ptrCast(&metrics), &ascent) orelse return error.AtlasCreationFailed;
        const pipeline = objc.create_text_pipeline(device) orelse return error.PipelineCreationFailed;

        return TextRenderer{
            .atlas_texture = texture,
            .text_pipeline = pipeline,
            .glyph_metrics = metrics,
            .font_size = font_size,
            .font_ascent = ascent,
        };
    }

    /// Write glyph vertices into a TextBatch for batched submission.
    /// Flushes the batch via the provided callback when it fills up.
    pub fn generateVertices(
        self: *const TextRenderer,
        batch: *batch_mod.TextBatch,
        text_str: []const u8,
        x: f32,
        y: f32,
        r: f32,
        g: f32,
        b: f32,
        a: f32,
    ) void {
        var cur_x = x;
        for (text_str) |c| {
            if (c < 32 or c > 126) continue;
            const idx = c - 32;
            const m = self.glyph_metrics[idx];
            const gx = cur_x + m.bearing_x;
            const gy = y + self.font_ascent - m.bearing_y - m.height;
            batch.appendQuad(gx, gy, m.width, m.height, m.uv_x, m.uv_y, m.uv_w, m.uv_h, r, g, b, a);
            cur_x += m.advance;
        }
    }

    /// Legacy per-glyph draw path used by renderer fallback.
    pub fn drawText(self: *const TextRenderer, fc: *anyopaque, text_str: []const u8, x: f32, y: f32, r: f32, g: f32, b: f32, a: f32) void {
        objc.set_pipeline(fc, self.text_pipeline);

        var cur_x = x;
        for (text_str) |c| {
            if (c < 32 or c > 126) continue;
            const idx = c - 32;
            const m = self.glyph_metrics[idx];

            const gx = cur_x + m.bearing_x;
            const gy = y + self.font_ascent - m.bearing_y - m.height;

            objc.draw_text_quad(fc, self.atlas_texture, gx, gy, m.width, m.height, m.uv_x, m.uv_y, m.uv_w, m.uv_h, r, g, b, a);
            cur_x += m.advance;
        }
    }
};
