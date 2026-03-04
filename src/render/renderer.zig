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

const js = @import("../js/mod.zig");
const dom = @import("../dom/mod.zig");
const css = @import("../css/mod.zig");

pub const FrameContext = struct {
    timer_queue: *js.timers.TimerQueue,
    raf_queue: *js.raf.RafQueue,
    event_dispatcher: *js.event_dispatch.EventDispatcher,
    pipeline_state: *js.pipeline.PipelineState,
};

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
    frame_ctx: ?FrameContext = null,
    document: ?*dom.Document = null,
    stylesheets: []const css.Stylesheet = &.{},
    styled_root: ?*css.StyledNode = null,

    pub fn init() !Renderer {
        // MTLCreateSystemDefaultDevice
        const device = MTLCreateSystemDefaultDevice() orelse return error.NoMetalDevice;

        const queue = objc.create_command_queue(device) orelse return error.QueueCreationFailed;

        const pipeline = objc.create_render_pipeline(device) orelse return error.PipelineCreationFailed;

        const scale_factor = objc.get_screen_scale_factor();
        const text_renderer = try text.TextRenderer.init(device, queue, 64.0, scale_factor);

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

    pub fn setFrameContext(self: *Renderer, ctx: FrameContext) void {
        self.frame_ctx = ctx;
    }

    pub fn setRenderContext(self: *Renderer, doc: *dom.Document, sheets: []const css.Stylesheet) void {
        self.document = doc;
        self.stylesheets = sheets;
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
                        const click = self.interaction.handleClick(root, event.x, event.y, self.scroll.scroll_y);
                        if (click.target_node) |target| {
                            if (self.frame_ctx) |*fc| {
                                _ = fc.event_dispatcher.dispatchEvent(@constCast(target), "click");
                            }
                        }
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

        if (self.frame_ctx) |*fc| {
            const now_ms = std.time.milliTimestamp();
            fc.timer_queue.tick(now_ms);
            fc.raf_queue.tick(@as(f64, @floatFromInt(now_ms)));
        }

        if (self.frame_ctx) |*fc| {
            if (fc.pipeline_state.isDirty()) {
                self.rebuildRenderTree();
                fc.pipeline_state.clearDirty();
            }
        }

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

    fn rebuildRenderTree(self: *Renderer) void {
        const alloc = self.allocator orelse return;
        const doc = self.document orelse return;

        if (self.styled_root) |old_styled| {
            var res = css.StyleResolver.init(alloc);
            res.freeStyledNode(@constCast(old_styled));
        }

        var resolver = css.StyleResolver.init(alloc);
        const new_styled = resolver.resolve(doc.root, self.stylesheets) catch return;
        self.styled_root = new_styled;

        const new_layout = layout_box.buildLayoutTree(alloc, new_styled) catch return;

        var vw: f32 = 1280;
        var vh: f32 = 800;
        if (self.view) |view| {
            var width: f32 = 0;
            var height: f32 = 0;
            objc.get_drawable_size(view, &width, &height);
            if (width > 0) vw = width;
            if (height > 0) vh = height;
        }

        const lctx = layout_mod.LayoutContext{
            .allocator = alloc,
            .viewport_width = vw,
            .viewport_height = vh,
        };
        layout_mod.layoutTree(new_layout, lctx);

        const new_dl = display_list_mod.buildDisplayList(alloc, new_layout) catch {
            new_layout.deinit(alloc);
            alloc.destroy(new_layout);
            return;
        };

        if (self.layout_root) |old_root| {
            if (self.owned_display_list) |*old_dl| {
                old_dl.deinit();
            }
            old_root.deinit(alloc);
            alloc.destroy(old_root);
        }

        self.layout_root = new_layout;
        self.owned_display_list = new_dl;
        self.scroll.setContentHeight(new_layout.dimensions.marginBox().height);
    }
};
