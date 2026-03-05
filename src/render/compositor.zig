const std = @import("std");
const app = @import("../platform/app.zig");
const objc = app.objc;
const DisplayList = @import("display_list.zig").DisplayList;
const TextRenderer = @import("text.zig").TextRenderer;
const batch_mod = @import("batch.zig");

pub const PipelineKind = enum { none, rect, text, image };

pub fn isVisible(rect_y: f32, rect_height: f32, scroll_y: f32, viewport_height: f32) bool {
    const relative_y = rect_y - scroll_y;
    if (relative_y + rect_height <= 0) return false;
    if (relative_y >= viewport_height) return false;
    return true;
}

/// Flush pending rect vertices to the GPU via a single batched draw call.
fn flushRects(fc: *anyopaque, device: *anyopaque, pipeline: *anyopaque, batch: *batch_mod.RectBatch) void {
    if (batch.vertexCount() == 0) return;
    objc.set_pipeline(fc, pipeline);
    objc.batch_solid_rects(fc, device, @ptrCast(&batch.vertices), @intCast(batch.vertexCount()));
    batch.clear();
}

/// Flush pending text vertices to the GPU via a single batched draw call.
fn flushText(
    fc: *anyopaque,
    device: *anyopaque,
    text_renderer: *const TextRenderer,
    batch: *batch_mod.TextBatch,
) void {
    if (batch.vertexCount() == 0) return;
    objc.set_pipeline(fc, text_renderer.text_pipeline);
    objc.batch_text_quads(fc, device, text_renderer.atlas_texture, @ptrCast(&batch.vertices), @intCast(batch.vertexCount()));
    batch.clear();
}

/// Flush both rect and text batches.
fn flushAll(
    fc: *anyopaque,
    device: *anyopaque,
    rect_pipeline: *anyopaque,
    text_renderer: *const TextRenderer,
    rect_batch: *batch_mod.RectBatch,
    text_batch: *batch_mod.TextBatch,
) void {
    flushRects(fc, device, rect_pipeline, rect_batch);
    flushText(fc, device, text_renderer, text_batch);
}

pub const Compositor = struct {
    rect_pipeline: *anyopaque,
    text_renderer: *const TextRenderer,
    image_pipeline: ?*anyopaque = null,
    device: *anyopaque,

    pub fn render(
        self: *const Compositor,
        fc: *anyopaque,
        view: *anyopaque,
        display_list: *const DisplayList,
        scroll_y: f32,
    ) void {
        var width: f32 = 0;
        var height: f32 = 0;
        objc.get_drawable_size(view, &width, &height);

        const scale = objc.get_content_scale(view);

        objc.set_projection(fc, width, height);

        var rect_batch: batch_mod.RectBatch = .{};
        var text_batch: batch_mod.TextBatch = .{};
        var current: PipelineKind = .none;
        for (display_list.commands.items) |cmd| {
            switch (cmd) {
                .draw_rect => |r| {
                    if (!isVisible(r.rect.y, r.rect.height, scroll_y, height)) continue;
                    if (current != .rect) {
                        flushText(fc, self.device, self.text_renderer, &text_batch);
                        current = .rect;
                    }
                    if (rect_batch.isFull()) {
                        flushRects(fc, self.device, self.rect_pipeline, &rect_batch);
                    }
                    const rf = @as(f32, @floatFromInt(r.color.r)) / 255.0;
                    const gf = @as(f32, @floatFromInt(r.color.g)) / 255.0;
                    const bf = @as(f32, @floatFromInt(r.color.b)) / 255.0;
                    const af = @as(f32, @floatFromInt(r.color.a)) / 255.0;
                    rect_batch.appendRect(r.rect.x, r.rect.y - scroll_y, r.rect.width, r.rect.height, rf, gf, bf, af);
                },
                .draw_text => |t| {
                    if (!isVisible(t.rect.y, t.rect.height, scroll_y, height)) {
                        continue;
                    }
                    if (current != .text) {
                        flushRects(fc, self.device, self.rect_pipeline, &rect_batch);
                        current = .text;
                    }
                    if (text_batch.isFull()) {
                        flushText(fc, self.device, self.text_renderer, &text_batch);
                    }
                    const rf = @as(f32, @floatFromInt(t.color.r)) / 255.0;
                    const gf = @as(f32, @floatFromInt(t.color.g)) / 255.0;
                    const bf = @as(f32, @floatFromInt(t.color.b)) / 255.0;
                    const af = @as(f32, @floatFromInt(t.color.a)) / 255.0;
                    const is_bold = t.font_weight >= 700;
                    if (is_bold and self.text_renderer.bold_atlas_texture != null) {
                        // Flush any pending regular text first
                        flushText(fc, self.device, self.text_renderer, &text_batch);
                        // Generate vertices using bold metrics
                        self.text_renderer.generateBoldVertices(&text_batch, t.text, t.rect.x, t.rect.y - scroll_y, rf, gf, bf, af, t.font_size, t.rect.width, scale);
                        // Flush bold text with bold atlas
                        if (text_batch.vertexCount() > 0) {
                            objc.set_pipeline(fc, self.text_renderer.text_pipeline);
                            objc.batch_text_quads(fc, self.device, self.text_renderer.bold_atlas_texture.?, @ptrCast(&text_batch.vertices), @intCast(text_batch.vertexCount()));
                            text_batch.clear();
                        }
                    } else {
                        self.text_renderer.generateVertices(&text_batch, t.text, t.rect.x, t.rect.y - scroll_y, rf, gf, bf, af, t.font_size, t.rect.width, scale);
                    }
                },
                .push_clip => |rect| {
                    flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
                    current = .none;
                    objc.set_scissor_rect(fc, rect.x * scale, (rect.y - scroll_y) * scale, rect.width * scale, rect.height * scale, height * scale);
                },
                .draw_image => |img| {
                    if (!isVisible(img.rect.y, img.rect.height, scroll_y, height)) continue;
                    // Flush everything before switching to image pipeline
                    flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
                    current = .image;

                    if (self.image_pipeline) |img_pipeline| {
                        // Build 6 vertices for a textured quad with full UV
                        const x = img.rect.x;
                        const y = img.rect.y - scroll_y;
                        const w = img.rect.width;
                        const h = img.rect.height;
                        const vertices = [6][8]f32{
                            .{ x, y, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0 },     // top-left
                            .{ x + w, y, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0 }, // top-right
                            .{ x, y + h, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0 }, // bottom-left
                            .{ x + w, y, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0 }, // top-right
                            .{ x, y + h, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0 }, // bottom-left
                            .{ x + w, y + h, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 }, // bottom-right
                        };
                        objc.set_pipeline(fc, img_pipeline);
                        objc.batch_image_quads(fc, self.device, img.texture, @ptrCast(&vertices), 6);
                    }
                },
                .pop_clip => {
                    flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
                    current = .none;
                    objc.reset_scissor_rect(fc, width * scale, height * scale);
                },
            }
        }

        flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
    }
};
