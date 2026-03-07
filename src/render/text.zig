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
    // Bold variant
    bold_atlas_texture: ?*anyopaque = null,
    bold_glyph_metrics: [95]objc.GlyphMetrics = undefined,
    bold_font_ascent: f32 = 0,
    // Italic variant
    italic_atlas_texture: ?*anyopaque = null,
    italic_glyph_metrics: [95]objc.GlyphMetrics = undefined,
    italic_font_ascent: f32 = 0,

    pub fn init(device: *anyopaque, queue: *anyopaque, font_size: f32, scale_factor: f32) !TextRenderer {
        var metrics: [95]objc.GlyphMetrics = undefined;
        var ascent: f32 = 0;
        const texture = objc.create_font_atlas(device, queue, font_size, scale_factor, @ptrCast(&metrics), &ascent) orelse return error.AtlasCreationFailed;
        const pipeline = objc.create_text_pipeline(device) orelse return error.PipelineCreationFailed;

        // Create bold atlas
        var bold_metrics: [95]objc.GlyphMetrics = undefined;
        var bold_ascent: f32 = 0;
        const bold_texture = objc.create_bold_font_atlas(device, queue, font_size, scale_factor, @ptrCast(&bold_metrics), &bold_ascent);

        // Create italic atlas
        var italic_metrics: [95]objc.GlyphMetrics = undefined;
        var italic_ascent: f32 = 0;
        const italic_texture = objc.create_font_atlas_ext(device, queue, "Helvetica", font_size, 400.0, true, scale_factor, @ptrCast(&italic_metrics), &italic_ascent);

        return TextRenderer{
            .atlas_texture = texture,
            .text_pipeline = pipeline,
            .glyph_metrics = metrics,
            .font_size = font_size,
            .font_ascent = ascent,
            .bold_atlas_texture = bold_texture,
            .bold_glyph_metrics = bold_metrics,
            .bold_font_ascent = bold_ascent,
            .italic_atlas_texture = italic_texture,
            .italic_glyph_metrics = italic_metrics,
            .italic_font_ascent = italic_ascent,
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

                const snapped_x = @round(gx * device_scale) / device_scale;
                const snapped_y = @round(gy * device_scale) / device_scale;

                batch.appendQuad(snapped_x, snapped_y, sw, sh, m.uv_x, m.uv_y, m.uv_w, m.uv_h, r, g, b, a);
                cur_x += m.advance * scale;
            }
            first_word = false;
        }
    }

    /// Generate vertices using the bold font atlas metrics.
    pub fn generateBoldVertices(
        self: *const TextRenderer,
        batch: *batch_mod.TextBatch,
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
        const space_advance = self.bold_glyph_metrics[0].advance * scale;

        var cur_x = x;
        var cur_y = y;

        var it = std.mem.tokenizeAny(u8, text_str, " ");
        var first_word = true;

        while (it.next()) |word| {
            var word_width: f32 = 0;
            for (word) |c| {
                if (c < 32 or c > 126) continue;
                const idx = c - 32;
                word_width += self.bold_glyph_metrics[idx].advance * scale;
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
                const m = self.bold_glyph_metrics[idx];
                const sw = m.width * scale;
                const sh = m.height * scale;
                const scaled_ascent = self.bold_font_ascent * scale;
                const gx = cur_x + m.bearing_x * scale;
                const gy = cur_y + scaled_ascent - m.bearing_y * scale - sh;

                const snapped_x = @round(gx * device_scale) / device_scale;
                const snapped_y = @round(gy * device_scale) / device_scale;

                batch.appendQuad(snapped_x, snapped_y, sw, sh, m.uv_x, m.uv_y, m.uv_w, m.uv_h, r, g, b, a);
                cur_x += m.advance * scale;
            }
            first_word = false;
        }
    }

    /// Generate vertices using the italic font atlas metrics.
    pub fn generateItalicVertices(
        self: *const TextRenderer,
        batch: *batch_mod.TextBatch,
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
        const space_advance = self.italic_glyph_metrics[0].advance * scale;

        var cur_x = x;
        var cur_y = y;

        var it = std.mem.tokenizeAny(u8, text_str, " ");
        var first_word = true;

        while (it.next()) |word| {
            var word_width: f32 = 0;
            for (word) |c| {
                if (c < 32 or c > 126) continue;
                const idx = c - 32;
                word_width += self.italic_glyph_metrics[idx].advance * scale;
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
                const m = self.italic_glyph_metrics[idx];
                const sw = m.width * scale;
                const sh = m.height * scale;
                const scaled_ascent = self.italic_font_ascent * scale;
                const gx = cur_x + m.bearing_x * scale;
                const gy = cur_y + scaled_ascent - m.bearing_y * scale - sh;

                const snapped_x = @round(gx * device_scale) / device_scale;
                const snapped_y = @round(gy * device_scale) / device_scale;

                batch.appendQuad(snapped_x, snapped_y, sw, sh, m.uv_x, m.uv_y, m.uv_w, m.uv_h, r, g, b, a);
                cur_x += m.advance * scale;
            }
            first_word = false;
        }
    }
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

    /// Draw text at a specific size by scaling the atlas glyphs.
    /// This is a synchronous path intended for UI elements like the URL bar.
    pub fn drawTextScaled(self: *const TextRenderer, fc: *anyopaque, text_str: []const u8, x: f32, y: f32, target_size: f32, r: f32, g: f32, b: f32, a: f32) void {
        objc.set_pipeline(fc, self.text_pipeline);

        const scale = target_size / self.font_size;
        var cur_x = x;
        for (text_str) |c| {
            if (c < 32 or c > 126) continue;
            const idx = c - 32;
            const m = self.glyph_metrics[idx];

            const sw = m.width * scale;
            const sh = m.height * scale;
            const gx = cur_x + m.bearing_x * scale;
            const gy = y + (self.font_ascent * scale) - (m.bearing_y * scale) - sh;

            objc.draw_text_quad(fc, self.atlas_texture, gx, gy, sw, sh, m.uv_x, m.uv_y, m.uv_w, m.uv_h, r, g, b, a);
            cur_x += m.advance * scale;
        }
    }
};
