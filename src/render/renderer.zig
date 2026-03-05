const std = @import("std");
const app = @import("../platform/app.zig");
const objc = app.objc;
const text = @import("text.zig");
const compositor = @import("compositor.zig");
const scroll_mod = @import("scroll.zig");
const DisplayList = @import("display_list.zig").DisplayList;
const events = @import("../platform/events.zig");
const layout_mod = @import("../layout/mod.zig");
const ui = @import("../ui/mod.zig");
const hit_test = @import("hit_test.zig");

const display_list_mod = @import("display_list.zig");
const interaction_mod = @import("interaction.zig");
const text_measure = @import("../layout/text_measure.zig");

const js = @import("../js/mod.zig");
const dom = @import("../dom/mod.zig");
const css = @import("../css/mod.zig");
const net = @import("../net/mod.zig");

pub const NavigationContext = struct {
    fetch_client: *net.fetch.FetchClient,
    base_url: net.url.Url,
    js_bridge: *const js.context.JsBridge,
    console_log: ?*const anyopaque = null,
    console_warn: ?*const anyopaque = null,
    console_error: ?*const anyopaque = null,
};

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
    clear_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
    owned_display_list: ?display_list_mod.DisplayList = null,
    layout_root: ?*layout_mod.LayoutBox = null,
    allocator: ?std.mem.Allocator = null,
    scroll: scroll_mod.ScrollController = .{},
    interaction: interaction_mod.InteractionHandler = .{},
    input_manager: ui.input.InputManager,
    frame_ctx: ?FrameContext = null,
    document: ?*dom.Document = null,
    stylesheets: []const css.Stylesheet = &.{},
    styled_root: ?*css.StyledNode = null,
    nav_ctx: ?NavigationContext = null,
    pending_url: [4096]u8 = undefined,
    pending_url_len: usize = 0,

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
            .interaction = .{},
            .input_manager = ui.input.InputManager.init(),
        };
    }

    pub fn setClearColor(self: *Renderer, color: [4]f32) void {
        self.clear_color = color;
        if (self.view) |v| {
            objc.set_clear_color(v, color[0], color[1], color[2], color[3]);
        }
    }

    pub fn setDocument(self: *Renderer, alloc: std.mem.Allocator, root: *layout_mod.LayoutBox, dl: DisplayList) void {
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
                            if (target.node_type == .element and (target.tag == .input or target.tag == .textarea)) {
                                // Focus input — do NOT navigate
                                self.input_manager.focus(@constCast(target));
                            } else {
                                self.input_manager.blur();
                                // Only navigate links when the target is not an input
                                if (click.href) |href| {
                                    self.queueNavigation(href);
                                }
                            }
                            if (self.frame_ctx) |*fc| {
                                _ = fc.event_dispatcher.dispatchEvent(@constCast(target), "click");
                            }
                            // Rebuild display list so cursor appears/disappears
                            if (self.allocator) |alloc| {
                                if (self.owned_display_list) |*old_dl| {
                                    old_dl.deinit();
                                }
                                self.owned_display_list = display_list_mod.buildDisplayList(alloc, root, self.input_manager.focused_node) catch null;
                            }
                        }
                    }
                },
                .key_down => {
                    var handled = false;
                    std.debug.print("[KEY] key_down: keycode={d} text={any} focused={}\n", .{ event.keycode, event.text[0..4].*, self.input_manager.focused_node != null });
                    if (self.allocator) |alloc| {
                        const input_res = self.input_manager.handleEvent(alloc, event) catch |err| blk: {
                            std.debug.print("[KEY] handleEvent error: {}\n", .{err});
                            break :blk .ignored;
                        };
                        std.debug.print("[KEY] handleEvent result: {}\n", .{input_res});
                        if (input_res == .submit) {
                            if (self.input_manager.focused_node) |node| {
                                self.handleFormSubmission(node);
                            }
                            handled = true;
                        } else if (input_res == .handled) {
                            handled = true;
                            // Trigger layout update
                            if (self.layout_root) |root| {
                                var window_width: f32 = 1280.0;
                                var window_height: f32 = 800.0;
                                if (self.view) |v| {
                                    objc.get_drawable_size(v, &window_width, &window_height);
                                }
                                const ctx = layout_mod.LayoutContext{
                                    .allocator = alloc,
                                    .viewport_width = window_width, // Could also get actual viewport
                                    .viewport_height = window_height,
                                };
                                layout_mod.layoutTree(root, ctx);
                                if (self.owned_display_list) |*old_dl| {
                                    old_dl.deinit();
                                }
                                self.owned_display_list = display_list_mod.buildDisplayList(alloc, root, self.input_manager.focused_node) catch null;
                            }
                        }
                    }
                    if (!handled) {
                        if (interaction_mod.InteractionHandler.handleKeyDown(event.keycode, event.modifiers)) |action| {
                            switch (action) {
                                .quit => terminate_application(),
                                .scroll_up => self.scroll.scrollBy(-self.scroll.viewport_height),
                                .scroll_down => self.scroll.scrollBy(self.scroll.viewport_height),
                                .scroll_to_top => self.scroll.setScrollY(0),
                                .scroll_to_bottom => self.scroll.setScrollY(self.scroll.content_height - self.scroll.viewport_height),
                            }
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
                            self.owned_display_list = display_list_mod.buildDisplayList(alloc, root, self.input_manager.focused_node) catch null;
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

        // Process pending navigation
        if (self.pending_url_len > 0) {
            const url_copy = self.pending_url[0..self.pending_url_len];
            std.debug.print("Navigating to: {s}\n", .{url_copy});
            self.navigateTo(url_copy);
            self.pending_url_len = 0;
        }

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
                            .image_pipeline = objc.create_image_pipeline(self.device),
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

        const new_layout = layout_mod.buildLayoutTree(alloc, new_styled) catch return;

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

        const new_dl = display_list_mod.buildDisplayList(alloc, new_layout, self.input_manager.focused_node) catch {
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

    fn queueNavigation(self: *Renderer, href: []const u8) void {
        const nav = self.nav_ctx orelse return;
        const alloc = self.allocator orelse return;

        // Resolve relative URLs
        if (std.mem.startsWith(u8, href, "http://") or std.mem.startsWith(u8, href, "https://")) {
            const len = @min(href.len, self.pending_url.len);
            @memcpy(self.pending_url[0..len], href[0..len]);
            self.pending_url_len = len;
        } else if (std.mem.startsWith(u8, href, "#")) {
            return; // Fragment-only, skip for now
        } else {
            const resolved = net.url.Url.resolve(alloc, nav.base_url, href) catch return;
            defer alloc.free(resolved);
            const len = @min(resolved.len, self.pending_url.len);
            @memcpy(self.pending_url[0..len], resolved[0..len]);
            self.pending_url_len = len;
        }
    }

    fn navigateTo(self: *Renderer, url_str: []const u8) void {
        const alloc = self.allocator orelse return;
        var nav = self.nav_ctx orelse return;

        // 1. Fetch the new page
        std.debug.print("Fetching: {s}\n", .{url_str});
        var resp = nav.fetch_client.fetch(.{ .url = url_str }) catch |err| {
            std.debug.print("Navigation failed: {}\n", .{err});
            return;
        };

        // Free response headers (not needed for page load)
        for (resp.headers) |hdr| {
            alloc.free(hdr.name);
            alloc.free(hdr.value);
        }
        if (resp.headers.len > 0) alloc.free(resp.headers);
        resp.headers = &[_]net.types.HttpHeader{};

        if (resp.status_code != 200) {
            std.debug.print("Navigation HTTP error: {d}\n", .{resp.status_code});
            resp.deinit(alloc);
            return;
        }

        // 2. Update base URL
        nav.base_url = net.url.Url.parse(url_str) catch nav.base_url;
        self.nav_ctx = nav;

        // 3. Parse HTML
        const new_doc = dom.builder.parseHTML(alloc, resp.body) catch {
            alloc.free(resp.body);
            return;
        };
        alloc.free(resp.body);

        // 4. Discover and load sub-resources
        var resource_loader = net.loader.ResourceLoader.init(alloc, nav.fetch_client, nav.base_url);
        const refs = resource_loader.discoverResources(new_doc.root) catch &[_]net.loader.ResourceRef{};
        const loaded = resource_loader.loadResources(refs) catch &[_]net.loader.LoadedResource{};

        if (refs.len > 0) {
            std.debug.print("[nav] Discovered {d} sub-resources\n", .{refs.len});
        }

        // 5. Build stylesheets (UA + inline + external CSS)
        const ua_sheet = css.user_agent.getStylesheet(alloc) catch return;
        const page_sheets = css.style_extract.extractStylesheets(alloc, new_doc.root) catch &[_]css.Stylesheet{};
        var all_sheets = std.ArrayListUnmanaged(css.Stylesheet){};
        all_sheets.append(alloc, ua_sheet) catch return;
        for (page_sheets) |s| all_sheets.append(alloc, s) catch {};

        // Parse external CSS
        for (loaded) |res| {
            switch (res.type) {
                .CSS => {
                    std.debug.print("[nav] Applying CSS: {s}\n", .{res.url});
                    const sheet = css.parser.Parser.parse(alloc, res.body) catch continue;
                    all_sheets.append(alloc, sheet) catch {};
                },
                else => {},
            }
        }

        // 6. Free old state
        if (self.document) |old_doc| {
            old_doc.deinit();
        }

        // 7. Update renderer state
        self.document = new_doc;
        self.stylesheets = all_sheets.items;

        // 8. Rebuild render tree (style resolve + layout + display list)
        self.rebuildRenderTree();
        self.scroll.setScrollY(0);

        // Cleanup sub-resource refs
        for (refs) |ref| alloc.free(ref.url);
        alloc.free(refs);
        for (loaded) |*res| @constCast(res).deinit(alloc);
        alloc.free(loaded);

        std.debug.print("Navigation complete\n", .{});
    }

    fn handleFormSubmission(self: *Renderer, input_node: *@import("../dom/node.zig").Node) void {
        var current: ?*@import("../dom/node.zig").Node = input_node;
        var form_node: ?*@import("../dom/node.zig").Node = null;
        while (current) |node| {
            if (node.node_type == .element and node.tag == .form) {
                form_node = node;
                break;
            }
            current = node.parent;
        }
        
        if (form_node == null) return;
        
        const action = form_node.?.getAttribute("action") orelse "";
        const method = form_node.?.getAttribute("method") orelse "GET";
        
        if (!std.mem.eql(u8, method, "GET") and !std.mem.eql(u8, method, "get")) {
            std.debug.print("Form method {s} not supported yet\n", .{method});
        }

        if (self.allocator) |alloc| {
            var query = std.ArrayListUnmanaged(u8){};
            defer query.deinit(alloc);
            
            const Collect = struct {
                fn collectInputs(alloc2: std.mem.Allocator, n: *@import("../dom/node.zig").Node, q: *std.ArrayListUnmanaged(u8)) !void {
                    if (n.node_type == .element and (n.tag == .input or n.tag == .textarea)) {
                        if (n.getAttribute("name")) |name| {
                            const val = n.getAttribute("value") orelse "";
                            if (q.items.len > 0) try q.append(alloc2, '&');
                            
                            try q.appendSlice(alloc2, name);
                            try q.append(alloc2, '=');
                            for (val) |c| {
                                if (c == ' ') {
                                    try q.append(alloc2, '+');
                                } else {
                                    try q.append(alloc2, c);
                                }
                            }
                        }
                    }
                    for (n.children.items) |child| {
                        try collectInputs(alloc2, child, q);
                    }
                }
            };
            
            Collect.collectInputs(alloc, form_node.?, &query) catch return;
            
            var url_str = std.ArrayListUnmanaged(u8){};
            defer url_str.deinit(alloc);
            
            // Re-resolve action URL relative to current base URL if needed.
            // queueNavigation uses url.Url.resolve implicitly.
            url_str.appendSlice(alloc, action) catch return;
            if (query.items.len > 0) {
                if (std.mem.indexOfScalar(u8, action, '?') == null) {
                    url_str.append(alloc, '?') catch return;
                } else {
                    url_str.append(alloc, '&') catch return;
                }
                url_str.appendSlice(alloc, query.items) catch return;
            }
            
            std.debug.print("Submitting form to: {s}\n", .{url_str.items});
            self.queueNavigation(url_str.items);
        }
    }
};
