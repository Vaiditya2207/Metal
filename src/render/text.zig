const std = @import("std");
const app = @import("../platform/app.zig");
const objc = app.objc;
const batch_mod = @import("batch.zig");

// R-8 FIX: UTF-8 aware character iteration.
// Returns the glyph index (0-94) for printable ASCII, or maps non-ASCII codepoints
// to '?' (index 31) as a visible fallback instead of silently dropping them.
// Also returns the byte length consumed so callers can skip multi-byte sequences.
const GlyphResult = struct {
    index: ?u7, // null for control chars (skip), 0-94 for renderable
    byte_len: u3, // 1-4 bytes consumed
};

fn resolveGlyph(bytes: []const u8) GlyphResult {
    if (bytes.len == 0) return .{ .index = null, .byte_len = 1 };
    const b0 = bytes[0];

    // ASCII range
    if (b0 < 128) {
        if (b0 < 32 or b0 == 127) return .{ .index = null, .byte_len = 1 }; // Control chars: skip
        return .{ .index = @intCast(b0 - 32), .byte_len = 1 }; // Normal ASCII
    }

    // Multi-byte UTF-8: determine sequence length, skip all continuation bytes,
    // and render a single '?' replacement glyph.
    const replacement_idx: u7 = '?' - 32; // index 31
    if (b0 & 0xE0 == 0xC0) return .{ .index = replacement_idx, .byte_len = 2 };
    if (b0 & 0xF0 == 0xE0) return .{ .index = replacement_idx, .byte_len = 3 };
    if (b0 & 0xF8 == 0xF0) return .{ .index = replacement_idx, .byte_len = 4 };

    // Invalid UTF-8 lead byte: skip one byte, render '?'
    return .{ .index = replacement_idx, .byte_len = 1 };
}

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
            {
                var wi: usize = 0;
                while (wi < word.len) {
                    const gr = resolveGlyph(word[wi..]);
                    if (gr.index) |idx| {
                        word_width += self.glyph_metrics[idx].advance * scale;
                    }
                    wi += gr.byte_len;
                }
            }

            if (!first_word and cur_x + space_advance + word_width > x + max_width) {
                cur_x = x;
                cur_y += line_height;
            } else if (!first_word) {
                cur_x += space_advance;
            }

            {
                var wi: usize = 0;
                while (wi < word.len) {
                    const gr = resolveGlyph(word[wi..]);
                    wi += gr.byte_len;
                    const idx = gr.index orelse continue;
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
            {
                var wi: usize = 0;
                while (wi < word.len) {
                    const gr = resolveGlyph(word[wi..]);
                    if (gr.index) |idx| {
                        word_width += self.bold_glyph_metrics[idx].advance * scale;
                    }
                    wi += gr.byte_len;
                }
            }

            if (!first_word and cur_x + space_advance + word_width > x + max_width) {
                cur_x = x;
                cur_y += line_height;
            } else if (!first_word) {
                cur_x += space_advance;
            }

            {
                var wi: usize = 0;
                while (wi < word.len) {
                    const gr = resolveGlyph(word[wi..]);
                    wi += gr.byte_len;
                    const idx = gr.index orelse continue;
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
            {
                var wi: usize = 0;
                while (wi < word.len) {
                    const gr = resolveGlyph(word[wi..]);
                    if (gr.index) |idx| {
                        word_width += self.italic_glyph_metrics[idx].advance * scale;
                    }
                    wi += gr.byte_len;
                }
            }

            if (!first_word and cur_x + space_advance + word_width > x + max_width) {
                cur_x = x;
                cur_y += line_height;
            } else if (!first_word) {
                cur_x += space_advance;
            }

            {
                var wi: usize = 0;
                while (wi < word.len) {
                    const gr = resolveGlyph(word[wi..]);
                    wi += gr.byte_len;
                    const idx = gr.index orelse continue;
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
            }
            first_word = false;
        }
    }
    pub fn drawText(self: *const TextRenderer, fc: *anyopaque, text_str: []const u8, x: f32, y: f32, r: f32, g: f32, b: f32, a: f32) void {
        objc.set_pipeline(fc, self.text_pipeline);

        var cur_x = x;
        var i: usize = 0;
        while (i < text_str.len) {
            const gr = resolveGlyph(text_str[i..]);
            i += gr.byte_len;
            const idx = gr.index orelse continue;
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
        var i: usize = 0;
        while (i < text_str.len) {
            const gr = resolveGlyph(text_str[i..]);
            i += gr.byte_len;
            const idx = gr.index orelse continue;
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
