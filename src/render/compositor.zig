const std = @import("std");
const display_list_mod = @import("display_list.zig");
const DisplayCommand = display_list_mod.DisplayCommand;
const app = @import("../platform/app.zig");
const objc = app.objc;
const layout_box = @import("../layout/box.zig");
const text_mod = @import("text.zig");
const batch_mod = @import("batch.zig");

pub const PipelineKind = enum { none, rect, text, image };
const content_top_offset: f32 = 40.0;

pub fn isVisible(rect_y: f32, rect_height: f32, scroll_y: f32, viewport_height: f32, sticky_top: ?f32) bool {
    _ = rect_y; _ = rect_height; _ = scroll_y; _ = viewport_height; _ = sticky_top;
    return true; // DEBUG: Force all visible for now
}

pub const Compositor = struct {
    device: ?*anyopaque = null,
    rect_pipeline: ?*anyopaque = null,
    image_pipeline: ?*anyopaque = null,
    text_renderer: *text_mod.TextRenderer,
    allocator: std.mem.Allocator,
    command_queue: ?*anyopaque = null,
    svg_cache: ?*std.StringArrayHashMapUnmanaged(*anyopaque) = null,

    fn flushText(self: *const Compositor, fc: *anyopaque, device: *anyopaque, tr: *text_mod.TextRenderer, batch: *batch_mod.TextBatch) void {
        _ = self;
        const count = batch.vertexCount();
        if (count == 0) return;
        objc.set_pipeline(fc, tr.text_pipeline);
        objc.batch_text_quads(fc, device, tr.atlas_texture, @ptrCast(&batch.vertices), @intCast(count));
        batch.clear();
    }

    fn flushRects(self: *const Compositor, fc: *anyopaque, device: *anyopaque, pipeline: *anyopaque, batch: *batch_mod.RectBatch) void {
        _ = self;
        const count = batch.vertexCount();
        if (count == 0) return;
        objc.set_pipeline(fc, pipeline);
        objc.batch_solid_rects(fc, device, @ptrCast(&batch.vertices), @intCast(count));
        batch.clear();
    }

    pub fn render(
        self: *const Compositor,
        fc: *anyopaque,
        view: *anyopaque,
        display_list: *const display_list_mod.DisplayList,
        scroll_y: f32,
    ) void {
        var frame_width: f32 = 0;
        var frame_height: f32 = 0;
        objc.get_drawable_size(view, &frame_width, &frame_height);
        const scale = objc.get_content_scale(view);
        const content_height = if (frame_height > 40.0) frame_height - 40.0 else frame_height;

        // Reset scissor to full viewport at start
        objc.reset_scissor_rect(fc, frame_width, frame_height);

        std.debug.print("Compositor: render() - viewport={d}x{d}, commands={d}, scroll_y={d}\n", .{ frame_width, frame_height, display_list.commands.items.len, scroll_y });
        
        var rect_batch = batch_mod.RectBatch{};
        var text_batch = batch_mod.TextBatch{};
        
        var visible_count: usize = 0;
        var current: PipelineKind = .none;

        for (display_list.commands.items) |cmd| {
            switch (cmd) {
                .draw_rect => |r| {
                    const visible = isVisible(r.rect.y, r.rect.height, scroll_y, content_height, r.sticky_top);
                    if (visible) {
                        if (visible_count < 100) {
                            std.debug.print("Compositor: [RECT] at ({d}, {d}) size {d}x{d}, color=({d},{d},{d},{d})\n", .{ r.rect.x, r.rect.y, r.rect.width, r.rect.height, r.color.r, r.color.g, r.color.b, r.color.a });
                        }
                        visible_count += 1;
                    }
                    if (!visible) continue;
                    
                    if (current != .rect) {
                        self.flushText(fc, self.device.?, self.text_renderer, &text_batch);
                        current = .rect;
                    }
                    if (rect_batch.isFull()) {
                        self.flushRects(fc, self.device.?, self.rect_pipeline.?, &rect_batch);
                    }
                    var rf = @as(f32, @floatFromInt(r.color.r)) / 255.0;
                    var gf = @as(f32, @floatFromInt(r.color.g)) / 255.0;
                    var bf = @as(f32, @floatFromInt(r.color.b)) / 255.0;
                    const af = @as(f32, @floatFromInt(r.color.a)) / 255.0;

                    // DEBUG: Tint pure white
                    if (rf > 0.99 and gf > 0.99 and bf > 0.99) {
                        rf = 0.9; gf = 0.9; bf = 0.95;
                    }
                    
                    var y = if (r.fixed_to_viewport) r.rect.y else r.rect.y - scroll_y;
                    if (r.sticky_top) |st| y = @max(y, st);
                    
                    rect_batch.appendRect(r.rect.x, y + content_top_offset, r.rect.width, r.rect.height, rf, gf, bf, af);
                },
                .draw_text => |t| {
                    const visible = isVisible(t.rect.y, t.rect.height, scroll_y, content_height, t.sticky_top);
                    if (visible) {
                        if (visible_count < 100) {
                            std.debug.print("Compositor: [TEXT] at ({d}, {d}) size {d}x{d} '{s}'\n", .{ t.rect.x, t.rect.y, t.rect.width, t.rect.height, t.text[0..@min(t.text.len, 10)] });
                        }
                        visible_count += 1;
                    }
                    if (!visible) continue;
                    
                    if (current != .text) {
                        self.flushRects(fc, self.device.?, self.rect_pipeline.?, &rect_batch);
                        current = .text;
                    }
                    if (text_batch.isFull()) {
                        self.flushText(fc, self.device.?, self.text_renderer, &text_batch);
                    }
                    const rf = @as(f32, @floatFromInt(t.color.r)) / 255.0;
                    const gf = @as(f32, @floatFromInt(t.color.g)) / 255.0;
                    const bf = @as(f32, @floatFromInt(t.color.b)) / 255.0;
                    const af = @as(f32, @floatFromInt(t.color.a)) / 255.0;


                    const is_bold = t.font_weight >= 700;
                    const is_italic = t.font_style == .italic;

                    var y = if (t.fixed_to_viewport) t.rect.y else t.rect.y - scroll_y;
                    if (t.sticky_top) |st| y = @max(y, st);
                    y += content_top_offset;
                    
                    if (is_bold and self.text_renderer.bold_atlas_texture != null) {
                        self.flushText(fc, self.device.?, self.text_renderer, &text_batch);
                        self.text_renderer.generateBoldVertices(&text_batch, t.text, t.rect.x, y, rf, gf, bf, af, t.font_size, t.rect.width, scale);
                        objc.set_pipeline(fc, self.text_renderer.text_pipeline);
                        objc.batch_text_quads(fc, self.device.?, self.text_renderer.bold_atlas_texture.?, @ptrCast(&text_batch.vertices), @intCast(text_batch.vertexCount()));
                        text_batch.clear();
                    } else if (is_italic and self.text_renderer.italic_atlas_texture != null) {
                        self.flushText(fc, self.device.?, self.text_renderer, &text_batch);
                        self.text_renderer.generateItalicVertices(&text_batch, t.text, t.rect.x, y, rf, gf, bf, af, t.font_size, t.rect.width, scale);
                        objc.set_pipeline(fc, self.text_renderer.text_pipeline);
                        objc.batch_text_quads(fc, self.device.?, self.text_renderer.italic_atlas_texture.?, @ptrCast(&text_batch.vertices), @intCast(text_batch.vertexCount()));
                        text_batch.clear();
                    } else {
                        self.text_renderer.generateVertices(&text_batch, t.text, t.rect.x, y, rf, gf, bf, af, t.font_size, t.rect.width, scale);
                    }
                },
                .draw_image => |i| {
                    if (current != .image) {
                         self.flushRects(fc, self.device.?, self.rect_pipeline.?, &rect_batch);
                         self.flushText(fc, self.device.?, self.text_renderer, &text_batch);
                         current = .image;
                    }
                    var y = if (i.fixed_to_viewport) i.rect.y else i.rect.y - scroll_y;
                    if (i.sticky_top) |st| y = @max(y, st);
                    rect_batch.appendRect(i.rect.x, y + content_top_offset, i.rect.width, i.rect.height, 0.5, 0.5, 0.5, 1.0);
                },
                .draw_svg => |s| {
                     if (current != .rect) {
                         self.flushText(fc, self.device.?, self.text_renderer, &text_batch);
                         current = .rect;
                     }
                     var y = if (s.fixed_to_viewport) s.rect.y else s.rect.y - scroll_y;
                     if (s.sticky_top) |st| y = @max(y, st);
                     rect_batch.appendRect(s.rect.x, y + content_top_offset, s.rect.width, s.rect.height, 0.8, 0.8, 0.4, 1.0);
                },
                .push_clip => |rect| {
                    self.flushRects(fc, self.device.?, self.rect_pipeline.?, &rect_batch);
                    self.flushText(fc, self.device.?, self.text_renderer, &text_batch);
                    std.debug.print("Compositor: [CLIP] at ({d}, {d}) size {d}x{d}\n", .{ rect.x, rect.y, rect.width, rect.height });
                    objc.set_scissor_rect(fc, rect.x, rect.y + content_top_offset, rect.width, rect.height, frame_height);
                },
                .pop_clip => {
                    self.flushRects(fc, self.device.?, self.rect_pipeline.?, &rect_batch);
                    self.flushText(fc, self.device.?, self.text_renderer, &text_batch);
                    objc.reset_scissor_rect(fc, frame_width, frame_height);
                },
            }
        }

        self.flushRects(fc, self.device.?, self.rect_pipeline.?, &rect_batch);
        self.flushText(fc, self.device.?, self.text_renderer, &text_batch);
        std.debug.print("Compositor: render() - finished. visible_count={d}\n", .{ visible_count });
    }
};
