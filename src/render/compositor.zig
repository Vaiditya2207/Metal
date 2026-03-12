const std = @import("std");
const app = @import("../platform/app.zig");
const objc = app.objc;
const DisplayList = @import("display_list.zig").DisplayList;
const TextRenderer = @import("text.zig").TextRenderer;
const batch_mod = @import("batch.zig");

pub const PipelineKind = enum { none, rect, text, image };
const content_top_offset: f32 = 40.0;

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
    command_queue: ?*anyopaque = null,
    allocator: ?std.mem.Allocator = null,
    svg_cache: ?*std.StringArrayHashMapUnmanaged(*anyopaque) = null,

    pub fn render(
        self: *const Compositor,
        fc: *anyopaque,
        view: *anyopaque,
        display_list: *const DisplayList,
        scroll_y: f32,
    ) void {
        const Scissor = struct { x: f32, y: f32, w: f32, h: f32 };
        var scissor_stack: [16]Scissor = undefined;
        var scissor_depth: usize = 0;

        var width: f32 = 0;
        var height: f32 = 0;
        objc.get_drawable_size(view, &width, &height);
        const content_height = @max(0.0, height - content_top_offset);

        const scale = objc.get_content_scale(view);

        objc.set_projection(fc, width, height);

        // Clip everything to avoid content bleeding into the fixed toolbar (top 40px)
        const toolbar_scissor = Scissor{ .x = 0, .y = content_top_offset * scale, .w = width * scale, .h = content_height * scale };
        objc.set_scissor_rect(fc, toolbar_scissor.x, toolbar_scissor.y, toolbar_scissor.w, toolbar_scissor.h, height * scale);

        var current_scissor = toolbar_scissor;

        var rect_batch: batch_mod.RectBatch = .{};
        var text_batch: batch_mod.TextBatch = .{};
        var current: PipelineKind = .none;
        for (display_list.commands.items) |cmd| {
            switch (cmd) {
                .draw_rect => |r| {
                    if (!isVisible(r.rect.y, r.rect.height, scroll_y, content_height)) continue;
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
                    rect_batch.appendRect(r.rect.x, r.rect.y - scroll_y + content_top_offset, r.rect.width, r.rect.height, rf, gf, bf, af);
                },
                .draw_text => |t| {
                    if (!isVisible(t.rect.y, t.rect.height, scroll_y, content_height)) {
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
                    const is_italic = t.font_style == .italic;

                    if (is_bold and self.text_renderer.bold_atlas_texture != null) {
                        flushText(fc, self.device, self.text_renderer, &text_batch);
                        self.text_renderer.generateBoldVertices(&text_batch, t.text, t.rect.x, t.rect.y - scroll_y + content_top_offset, rf, gf, bf, af, t.font_size, t.rect.width, scale);
                        if (text_batch.vertexCount() > 0) {
                            objc.set_pipeline(fc, self.text_renderer.text_pipeline);
                            objc.batch_text_quads(fc, self.device, self.text_renderer.bold_atlas_texture.?, @ptrCast(&text_batch.vertices), @intCast(text_batch.vertexCount()));
                            text_batch.clear();
                        }
                    } else if (is_italic and self.text_renderer.italic_atlas_texture != null) {
                        flushText(fc, self.device, self.text_renderer, &text_batch);
                        self.text_renderer.generateItalicVertices(&text_batch, t.text, t.rect.x, t.rect.y - scroll_y + content_top_offset, rf, gf, bf, af, t.font_size, t.rect.width, scale);
                        if (text_batch.vertexCount() > 0) {
                            objc.set_pipeline(fc, self.text_renderer.text_pipeline);
                            objc.batch_text_quads(fc, self.device, self.text_renderer.italic_atlas_texture.?, @ptrCast(&text_batch.vertices), @intCast(text_batch.vertexCount()));
                            text_batch.clear();
                        }
                    } else {
                        self.text_renderer.generateVertices(&text_batch, t.text, t.rect.x, t.rect.y - scroll_y + content_top_offset, rf, gf, bf, af, t.font_size, t.rect.width, scale);
                    }
                },
                .push_clip => |rect| {
                    flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
                    current = .none;

                    if (scissor_depth < 16) {
                        scissor_stack[scissor_depth] = current_scissor;
                        scissor_depth += 1;
                    }

                    // Intersection of current and new clip
                    const new_x = @max(current_scissor.x, rect.x * scale);
                    const new_y = @max(current_scissor.y, (rect.y - scroll_y + content_top_offset) * scale);
                    const new_right = @min(current_scissor.x + current_scissor.w, (rect.x + rect.width) * scale);
                    const new_bottom = @min(current_scissor.y + current_scissor.h, (rect.y + rect.height - scroll_y + content_top_offset) * scale);

                    current_scissor = .{
                        .x = new_x,
                        .y = new_y,
                        .w = @max(0, new_right - new_x),
                        .h = @max(0, new_bottom - new_y),
                    };

                    objc.set_scissor_rect(fc, current_scissor.x, current_scissor.y, current_scissor.w, current_scissor.h, height * scale);
                },
                .draw_image => |img| {
                    if (!isVisible(img.rect.y, img.rect.height, scroll_y, content_height)) continue;
                    // Flush everything before switching to image pipeline
                    flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
                    current = .image;

                    if (self.image_pipeline) |img_pipeline| {
                        const x = img.rect.x;
                        const y = img.rect.y - scroll_y + content_top_offset;
                        const w = img.rect.width;
                        const h = img.rect.height;
                        const vertices = [6][8]f32{
                            .{ x, y, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0 },
                            .{ x + w, y, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0 },
                            .{ x, y + h, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
                            .{ x + w, y, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0 },
                            .{ x, y + h, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
                            .{ x + w, y + h, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
                        };
                        objc.set_pipeline(fc, img_pipeline);
                        objc.batch_image_quads(fc, self.device, img.texture, @ptrCast(&vertices), 6);
                    }
                },
                .draw_svg => |svg| {
                    if (!isVisible(svg.rect.y, svg.rect.height, scroll_y, content_height)) continue;

                    var texture: ?*anyopaque = null;
                    if (self.svg_cache) |cache| {
                        if (cache.get(svg.xml)) |tex| {
                            texture = tex;
                        } else if (self.allocator) |alloc| {
                            if (app.objc.rasterize_svg(self.device, self.command_queue, @ptrCast(svg.xml), svg.rect.width, svg.rect.height)) |tex| {
                                // R-2 FIX: Only cache if we can dupe the key.
                                // Previously, failed dupe fell back to svg.xml (display-list owned),
                                // causing use-after-free when the display list was rebuilt.
                                const owned_key = alloc.dupe(u8, svg.xml) catch null;
                                if (owned_key) |key| {
                                    cache.put(alloc, key, tex) catch {};
                                }
                                texture = tex;
                            }
                        }
                    }

                    if (texture) |tex| {
                        flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
                        current = .image;
                        if (self.image_pipeline) |img_pipeline| {
                            const x = svg.rect.x;
                            const y = svg.rect.y - scroll_y + content_top_offset;
                            const w = svg.rect.width;
                            const h = svg.rect.height;
                            const vertices = [6][8]f32{
                                .{ x, y, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ x + w, y, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ x, y + h, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ x + w, y, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ x, y + h, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ x + w, y + h, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
                            };
                            objc.set_pipeline(fc, img_pipeline);
                            objc.batch_image_quads(fc, self.device, tex, @ptrCast(&vertices), 6);
                        }
                    }
                },
                .pop_clip => {
                    flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
                    current = .none;

                    if (scissor_depth > 0) {
                        scissor_depth -= 1;
                        current_scissor = scissor_stack[scissor_depth];
                    } else {
                        // Fallback to toolbar
                        current_scissor = toolbar_scissor;
                    }
                    objc.set_scissor_rect(fc, current_scissor.x, current_scissor.y, current_scissor.w, current_scissor.h, height * scale);
                },
            }
        }

        flushAll(fc, self.device, self.rect_pipeline, self.text_renderer, &rect_batch, &text_batch);
    }
};
