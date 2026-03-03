const std = @import("std");
const app = @import("../platform/app.zig");
const objc = app.objc;
const DisplayList = @import("display_list.zig").DisplayList;
const TextRenderer = @import("text.zig").TextRenderer;
const batch_mod = @import("batch.zig");

pub const PipelineKind = enum { none, rect, text };

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
                    self.text_renderer.generateVertices(&text_batch, t.text, t.rect.x, t.rect.y - scroll_y, rf, gf, bf, af);
                },
                .push_clip => |rect| {
                    flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
                    current = .none;
                    objc.set_scissor_rect(fc, rect.x, rect.y - scroll_y, rect.width, rect.height, height);
                },
                .pop_clip => {
                    flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
                    current = .none;
                    objc.reset_scissor_rect(fc, width, height);
                },
            }
        }

        flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
    }
};
