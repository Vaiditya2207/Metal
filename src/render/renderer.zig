const std = @import("std");
const app = @import("../platform/app.zig");
const objc = app.objc;
const text = @import("text.zig");
const compositor = @import("compositor.zig");
const scroll_mod = @import("scroll.zig");
const DisplayList = @import("display_list.zig").DisplayList;
const events = @import("../platform/events.zig");
const layout_box = @import("../layout/box.zig");
const hit_test = @import("hit_test.zig");

const layout_mod = @import("../layout/layout.zig");
const display_list_mod = @import("display_list.zig");
const interaction_mod = @import("interaction.zig");

extern "C" fn MTLCreateSystemDefaultDevice() ?*anyopaque;
extern "C" fn set_cursor_style(style: i32) void;
extern "C" fn terminate_application() void;

pub const Renderer = struct {
    device: *anyopaque,
    command_queue: *anyopaque,
    pipeline_state: ?*anyopaque = null,
    text_renderer: ?text.TextRenderer = null,
    view: ?*anyopaque = null,
    clear_color: [4]f32 = .{ 0.1, 0.1, 0.1, 1.0 },
    owned_display_list: ?DisplayList = null,
    layout_root: ?*layout_box.LayoutBox = null,
    allocator: ?std.mem.Allocator = null,
    scroll: scroll_mod.ScrollController = .{},
    interaction: interaction_mod.InteractionHandler = .{},

    pub fn init() !Renderer {
        // MTLCreateSystemDefaultDevice
        const device = MTLCreateSystemDefaultDevice() orelse return error.NoMetalDevice;

        const queue = objc.create_command_queue(device) orelse return error.QueueCreationFailed;

        const pipeline = objc.create_render_pipeline(device) orelse return error.PipelineCreationFailed;

        const scale_factor = objc.get_screen_scale_factor();
        const text_renderer = try text.TextRenderer.init(device, 16.0, scale_factor);

        return Renderer{
            .device = device,
            .command_queue = queue,
            .pipeline_state = pipeline,
            .text_renderer = text_renderer,
        };
    }

    pub fn setClearColor(self: *Renderer, color: [4]f32) void {
        self.clear_color = color;
        if (self.view) |v| {
            objc.set_clear_color(v, color[0], color[1], color[2], color[3]);
        }
    }

    pub fn setDocument(self: *Renderer, alloc: std.mem.Allocator, root: *layout_box.LayoutBox, dl: DisplayList) void {
        self.allocator = alloc;
        self.layout_root = root;
        if (self.owned_display_list) |*old_dl| {
            old_dl.deinit();
        }
        self.owned_display_list = dl;
    }

    pub fn processEvents(self: *Renderer) void {
        while (events.global_queue.pop()) |event| {
            switch (event.event_type) {
                .scroll => {
                    self.scroll.scrollBy(event.y);
                },
                .mouse_moved => {
                    if (self.layout_root) |root| {
                        const old_state = self.interaction.cursor_state;
                        const new_state = self.interaction.handleMouseMove(root, event.x, event.y, self.scroll.scroll_y);
                        if (new_state != old_state) {
                            const style: i32 = switch (new_state) {
                                .default_cursor => 0,
                                .pointer => 1,
                                .text_cursor => 2,
                            };
                            set_cursor_style(style);
                        }
                    }
                },
                .mouse_down => {
                    if (self.layout_root) |root| {
                        _ = self.interaction.handleClick(root, event.x, event.y, self.scroll.scroll_y);
                    }
                },
                .key_down => {
                    if (interaction_mod.InteractionHandler.handleKeyDown(event.keycode, event.modifiers)) |action| {
                        switch (action) {
                            .quit => terminate_application(),
                            .scroll_up => self.scroll.scrollBy(-self.scroll.viewport_height),
                            .scroll_down => self.scroll.scrollBy(self.scroll.viewport_height),
                            .scroll_to_top => self.scroll.setScrollY(0),
                            .scroll_to_bottom => self.scroll.setScrollY(self.scroll.content_height - self.scroll.viewport_height),
                        }
                    }
                },
                .resize => {
                    if (self.layout_root) |root| {
                        if (self.allocator) |alloc| {
                            const ctx = layout_mod.LayoutContext{
                                .allocator = alloc,
                                .viewport_width = event.width,
                                .viewport_height = event.height,
                            };
                            layout_mod.layoutTree(root, ctx);
                            if (self.owned_display_list) |*old_dl| {
                                old_dl.deinit();
                            }
                            self.owned_display_list = display_list_mod.buildDisplayList(alloc, root) catch null;
                            self.scroll.setViewportHeight(event.height);
                            // Update content height from layout root
                            if (self.owned_display_list != null) {
                                self.scroll.setContentHeight(root.dimensions.marginBox().height);
                            }
                        }
                    }
                },
                else => {},
            }
        }
    }

    pub fn draw(ctx: ?*anyopaque) callconv(.c) void {
        if (ctx == null) return;
        const self: *Renderer = @ptrCast(@alignCast(ctx.?));

        self.scroll.tick();
        self.processEvents();

        const view = self.view orelse return;

        const frame_context = objc.begin_frame(self.command_queue, view);
        if (frame_context) |fc| {
            if (self.owned_display_list) |*dl| {
                if (self.pipeline_state) |ps| {
                    if (self.text_renderer) |*tr| {
                        const comp = compositor.Compositor{
                            .rect_pipeline = ps,
                            .text_renderer = tr,
                            .device = self.device,
                        };
                        comp.render(fc, view, dl, self.scroll.scroll_y);
                    }
                }
            } else {
                // Fallback test render
                var width: f32 = 0;
                var height: f32 = 0;
                objc.get_drawable_size(view, &width, &height);

                if (self.pipeline_state) |ps| {
                    objc.set_pipeline(fc, ps);
                    objc.set_projection(fc, width, height);
                    objc.draw_solid_rect(fc, 50, 50, 200, 100, 1.0, 0.0, 0.0, 1.0);
                }

                if (self.text_renderer) |tr| {
                    tr.drawText(fc, "Hello Metal (No Display List)", 50, 200, 1.0, 1.0, 1.0, 1.0);
                }
            }

            objc.end_frame(fc);
        }
    }
};
