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
const config = @import("../config.zig");

const display_list_mod = @import("display_list.zig");
const interaction_mod = @import("interaction.zig");
const text_measure = @import("../layout/text_measure.zig");

const js = @import("../js/mod.zig");
const dom = @import("../dom/mod.zig");
const css = @import("../css/mod.zig");
const net = @import("../net/mod.zig");
const jsc = @cImport({
    @cInclude("jsc_bridge.h");
});

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

const CachedImage = struct {
    texture: *anyopaque,
    width: f32,
    height: f32,
};

extern "C" fn MTLCreateSystemDefaultDevice() ?*anyopaque;
extern "C" fn set_cursor_style(style: i32) void;
extern "C" fn terminate_application() void;

fn textBaseline(tr: *text.TextRenderer, top: f32, height: f32, font_size: f32) f32 {
    const scale = font_size / tr.font_size;
    const ascent = tr.font_ascent * scale;
    return top + (height - font_size) * 0.5 + ascent;
}

pub const Renderer = struct {
    device: *anyopaque,
    command_queue: *anyopaque,
    pipeline_state: ?*anyopaque = null,
    image_pipeline: ?*anyopaque = null,
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
    stylesheets: std.ArrayListUnmanaged(css.Stylesheet) = .{},
    styled_root: ?*css.StyledNode = null,
    nav_ctx: ?NavigationContext = null,
    base_url_storage: ?[]u8 = null,
    js_ctx: ?*js.context.JsContext = null,
    resource_loader: ?net.loader.ResourceLoader = null,
    pending_url: [4096]u8 = undefined,
    pending_url_len: usize = 0,
    url_bar_focused: bool = false,
    url_bar_text: [4096]u8 = undefined,
    url_bar_len: usize = 0,

    history: [64][4096]u8 = undefined,
    history_len: [64]usize = undefined,
    history_count: usize = 0,
    history_pos: usize = 0,
    pending_is_history: bool = false,

    window: ?*anyopaque = null,
    page_title: [1024]u8 = undefined,
    page_title_len: usize = 0,
    favicon_texture: ?*anyopaque = null,
    image_cache: std.StringArrayHashMapUnmanaged(CachedImage) = .empty,
    svg_cache: std.StringArrayHashMapUnmanaged(*anyopaque) = .empty,
    loading_animation_time: f32 = 0.0,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,

    pub fn deinit(self: *Renderer) void {
        const alloc = self.allocator orelse return;
        if (self.base_url_storage) |u| {
            alloc.free(u);
            self.base_url_storage = null;
        }
        self.stylesheets.deinit(alloc);
        var img_it = self.image_cache.iterator();
        while (img_it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
        }
        self.image_cache.deinit(alloc);

        var it = self.svg_cache.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            // Metal textures are bridge-retained when returned from ObjC
            // We should release them here.
            // app.objc.release_texture(entry.value_ptr.*);
        }
        self.svg_cache.deinit(alloc);
    }

    pub fn setWindow(self: *Renderer, window_handle: *anyopaque) void {
        self.window = window_handle;
    }

    pub fn setJsContext(self: *Renderer, js_ctx: *js.context.JsContext) void {
        self.js_ctx = js_ctx;
    }

    fn findTitleNode(self: *Renderer, node: *dom.Node) ?*dom.Node {
        if (node.node_type == .element and node.tag == .title) {
            return node;
        }
        for (node.children.items) |child| {
            if (self.findTitleNode(child)) |found| return found;
        }
        return null;
    }

    fn goBack(self: *Renderer) void {
        if (self.history_pos > 1) {
            self.history_pos -= 1;
            const url = self.history[self.history_pos - 1][0..self.history_len[self.history_pos - 1]];
            self.queueHistoryNavigation(url);
        }
    }

    fn goForward(self: *Renderer) void {
        if (self.history_pos < self.history_count) {
            const url = self.history[self.history_pos][0..self.history_len[self.history_pos]];
            self.history_pos += 1;
            self.queueHistoryNavigation(url);
        }
    }

    fn reload(self: *Renderer) void {
        if (self.history_pos > 0) {
            const url = self.history[self.history_pos - 1][0..self.history_len[self.history_pos - 1]];
            self.queueHistoryNavigation(url);
        }
    }

    fn queueHistoryNavigation(self: *Renderer, url: []const u8) void {
        const len = @min(url.len, self.pending_url.len);
        @memcpy(self.pending_url[0..len], url[0..len]);
        self.pending_url_len = len;
        self.pending_is_history = true;
    }

    pub fn init() !Renderer {
        // MTLCreateSystemDefaultDevice
        const device = MTLCreateSystemDefaultDevice() orelse return error.NoMetalDevice;

        const queue = objc.create_command_queue(device) orelse return error.QueueCreationFailed;

        const pipeline = objc.create_render_pipeline(device) orelse return error.PipelineCreationFailed;

        // R-1 FIX: Create image pipeline once at init instead of per-frame.
        const img_pipeline = objc.create_image_pipeline(device);

        const scale_factor = objc.get_screen_scale_factor();
        const text_renderer = try text.TextRenderer.init(device, queue, 64.0, scale_factor);

        return Renderer{
            .device = device,
            .command_queue = queue,
            .pipeline_state = pipeline,
            .image_pipeline = img_pipeline,
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
        if (self.allocator) |alloc| {
            self.stylesheets.clearRetainingCapacity();
            self.stylesheets.appendSlice(alloc, sheets) catch {};
        }
        if (self.frame_ctx) |*fc| {
            fc.pipeline_state.markDirty();
        }
    }

    pub fn registerImageResource(self: *Renderer, url: []const u8, texture: *anyopaque, w: f32, h: f32) void {
        const alloc = self.allocator orelse return;
        if (self.image_cache.getPtr(url)) |entry| {
            entry.* = .{ .texture = texture, .width = w, .height = h };
        } else {
            const key = alloc.dupe(u8, url) catch return;
            self.image_cache.put(alloc, key, .{ .texture = texture, .width = w, .height = h }) catch {
                alloc.free(key);
                return;
            };
        }
        if (self.layout_root) |root| {
            self.attachImageToLayoutTree(root, url, texture, w, h);
        }
    }

    pub fn refreshDisplayList(self: *Renderer) void {
        const alloc = self.allocator orelse return;
        const root = self.layout_root orelse return;
        const new_dl = display_list_mod.buildDisplayList(alloc, root, self.input_manager.focused_node) catch return;
        if (self.owned_display_list) |*old_dl| {
            old_dl.deinit();
        }
        self.owned_display_list = new_dl;
    }

    fn clearImageCache(self: *Renderer) void {
        const alloc = self.allocator orelse return;
        var it = self.image_cache.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
        }
        self.image_cache.clearRetainingCapacity();
    }

    fn attachCachedImages(self: *Renderer, root: *layout_mod.LayoutBox) void {
        var it = self.image_cache.iterator();
        while (it.next()) |entry| {
            const cached = entry.value_ptr.*;
            self.attachImageToLayoutTree(root, entry.key_ptr.*, cached.texture, cached.width, cached.height);
        }
    }

    fn isTrackedImageUrl(self: *Renderer, abs_url: []const u8) bool {
        if (self.image_cache.get(abs_url) != null) return true;
        if (self.resource_loader) |*rl| {
            for (rl.pending.items) |pending| {
                if (pending.ref.type == .Image and std.mem.eql(u8, pending.ref.url, abs_url)) return true;
            }
            for (rl.loaded.items) |loaded| {
                if (loaded.type == .Image and std.mem.eql(u8, loaded.url, abs_url)) return true;
            }
        }
        return false;
    }

    fn refsContainUrl(refs: []const net.loader.ResourceRef, abs_url: []const u8) bool {
        for (refs) |ref| {
            if (std.mem.eql(u8, ref.url, abs_url)) return true;
        }
        return false;
    }

    fn collectBackgroundImageRefs(
        self: *Renderer,
        sn: *const css.StyledNode,
        refs: *std.ArrayListUnmanaged(net.loader.ResourceRef),
    ) !void {
        const alloc = self.allocator orelse return;
        const nav = self.nav_ctx orelse return;

        if (sn.style.background_image_url) |raw_url| {
            if (raw_url.len > 0 and !std.mem.startsWith(u8, raw_url, "data:")) {
                const abs_url = net.url.Url.resolve(alloc, nav.base_url, raw_url) catch null;
                if (abs_url) |resolved| {
                    if (self.isTrackedImageUrl(resolved) or refsContainUrl(refs.items, resolved)) {
                        alloc.free(resolved);
                    } else {
                        try refs.append(alloc, .{
                            .url = resolved,
                            .type = .Image,
                        });
                    }
                }
            }
        }

        for (sn.children) |child| {
            try self.collectBackgroundImageRefs(child, refs);
        }
    }

    fn queueBackgroundImageLoads(self: *Renderer, styled_root: *const css.StyledNode) void {
        const alloc = self.allocator orelse return;
        if (self.resource_loader == null) return;

        var refs = std.ArrayListUnmanaged(net.loader.ResourceRef){};
        defer {
            for (refs.items) |ref| alloc.free(ref.url);
            refs.deinit(alloc);
        }

        self.collectBackgroundImageRefs(styled_root, &refs) catch return;
        if (refs.items.len == 0) return;

        if (self.resource_loader) |*rl| {
            rl.startLoading(refs.items) catch |err| {
                std.debug.print("Failed to queue background images: {}\n", .{err});
                return;
            };
        }
    }

    fn styleImageUrlMatches(self: *Renderer, style_url: []const u8, loaded_url: []const u8) bool {
        if (style_url.len == 0) return false;
        if (std.mem.eql(u8, style_url, loaded_url)) return true;
        if (std.mem.endsWith(u8, loaded_url, style_url)) return true;

        const alloc = self.allocator orelse return false;
        const nav = self.nav_ctx orelse return false;
        const resolved = net.url.Url.resolve(alloc, nav.base_url, style_url) catch return false;
        defer alloc.free(resolved);

        return std.mem.eql(u8, resolved, loaded_url);
    }

    fn attachImageToLayoutTree(
        self: *Renderer,
        box: *layout_mod.LayoutBox,
        url: []const u8,
        texture: *anyopaque,
        w: f32,
        h: f32,
    ) void {
        if (box.styled_node) |sn| {
            if (sn.style.background_image_url) |bg_url| {
                if (self.styleImageUrlMatches(bg_url, url)) {
                    box.background_texture = texture;
                    box.background_intrinsic_width = w;
                    box.background_intrinsic_height = h;
                }
            }

            if (sn.node.node_type == .element and sn.node.tag == .img) {
                if (sn.node.getAttribute("src")) |src| {
                    if (std.mem.eql(u8, src, url) or std.mem.endsWith(u8, url, src)) {
                        box.image_texture = texture;
                        box.intrinsic_width = w;
                        box.intrinsic_height = h;
                    }
                }
            }
        }
        for (box.children.items) |child| {
            self.attachImageToLayoutTree(child, url, texture, w, h);
        }
    }

    fn logJsException(self: *Renderer, source_url: []const u8, script_body: []const u8) void {
        const js_ctx = self.js_ctx orelse return;
        const ex = jsc.jsc_get_exception(js_ctx.ctx);
        var preview: [161]u8 = undefined;
        const preview_len = @min(script_body.len, preview.len - 1);
        for (script_body[0..preview_len], 0..) |c, i| {
            preview[i] = if (c == '\n' or c == '\r' or c == '\t') ' ' else c;
        }
        preview[preview_len] = 0;

        if (ex == null) {
            std.debug.print("[JS EXCEPTION] {s} :: {s}\n", .{ source_url, preview[0..preview_len] });
            return;
        }

        const ex_str = jsc.jsc_value_to_string(js_ctx.ctx, ex);
        if (ex_str == null) {
            std.debug.print("[JS EXCEPTION] {s} :: {s}\n", .{ source_url, preview[0..preview_len] });
            jsc.jsc_clear_exception(js_ctx.ctx);
            return;
        }
        defer jsc.jsc_string_release(ex_str);

        var buf: [2048]u8 = undefined;
        const len = jsc.jsc_string_get_utf8(ex_str, &buf, @intCast(buf.len));
        if (len > 1) {
            std.debug.print("[JS EXCEPTION] {s} :: {s} :: {s}\n", .{ source_url, buf[0..@as(usize, @intCast(len - 1))], preview[0..preview_len] });
        } else {
            std.debug.print("[JS EXCEPTION] {s} :: {s}\n", .{ source_url, preview[0..preview_len] });
        }
        jsc.jsc_clear_exception(js_ctx.ctx);
    }

    pub fn processEvents(self: *Renderer) void {
        const ui_cfg = config.getConfig().ui;
        const toolbar_cfg = ui_cfg.toolbar;
        const toolbar_height = toolbar_cfg.height;
        const btn_size = toolbar_cfg.button_size;
        const btn_gap = toolbar_cfg.button_gap;
        const btn_y = @max(0.0, (toolbar_height - btn_size) * 0.5);
        const back_x = toolbar_cfg.padding_x;
        const fwd_x = back_x + btn_size + btn_gap;
        const reload_x = fwd_x + btn_size + btn_gap;
        const address_x = reload_x + btn_size + toolbar_cfg.address_gap;
        const address_height = @min(toolbar_cfg.address_height, toolbar_height);
        const address_y = (toolbar_height - address_height) * 0.5;

        while (events.global_queue.pop()) |event| {
            switch (event.event_type) {
                .scroll => {
                    self.scroll.scrollBy(event.y);
                },
                .mouse_moved => {
                    self.mouse_x = event.x;
                    self.mouse_y = event.y;
                    if (event.y < toolbar_height) {
                        const back_enabled = self.history_pos > 1;
                        const fwd_enabled = self.history_pos < self.history_count;
                        const reload_enabled = self.history_pos > 0;
                        const over_back = event.x >= back_x and event.x < back_x + btn_size and event.y >= btn_y and event.y < btn_y + btn_size;
                        const over_fwd = event.x >= fwd_x and event.x < fwd_x + btn_size and event.y >= btn_y and event.y < btn_y + btn_size;
                        const over_reload = event.x >= reload_x and event.x < reload_x + btn_size and event.y >= btn_y and event.y < btn_y + btn_size;
                        const over_address = event.x >= address_x and event.y >= address_y and event.y < address_y + address_height;

                        if ((over_back and back_enabled) or (over_fwd and fwd_enabled) or (over_reload and reload_enabled)) {
                            set_cursor_style(1); // pointer
                        } else if (over_address) {
                            set_cursor_style(2); // text cursor
                        } else {
                            set_cursor_style(0); // default
                        }
                    } else if (self.layout_root) |root| {
                        const old_state = self.interaction.cursor_state;
                        const new_state = self.interaction.handleMouseMove(root, event.x, event.y - toolbar_height, self.scroll.scroll_y);
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
                    if (event.y < toolbar_height) {
                        const back_enabled = self.history_pos > 1;
                        const fwd_enabled = self.history_pos < self.history_count;
                        const reload_enabled = self.history_pos > 0;
                        const over_back = event.x >= back_x and event.x < back_x + btn_size and event.y >= btn_y and event.y < btn_y + btn_size;
                        const over_fwd = event.x >= fwd_x and event.x < fwd_x + btn_size and event.y >= btn_y and event.y < btn_y + btn_size;
                        const over_reload = event.x >= reload_x and event.x < reload_x + btn_size and event.y >= btn_y and event.y < btn_y + btn_size;
                        const over_address = event.x >= address_x and event.y >= address_y and event.y < address_y + address_height;

                        if (over_back and back_enabled) {
                            self.goBack();
                        } else if (over_fwd and fwd_enabled) {
                            self.goForward();
                        } else if (over_reload and reload_enabled) {
                            self.reload();
                        } else if (over_address) {
                            self.url_bar_focused = true;
                            self.input_manager.blur();
                            set_cursor_style(2);
                        } else {
                            self.url_bar_focused = false;
                            set_cursor_style(0);
                        }
                    } else {
                        self.url_bar_focused = false;
                        if (self.layout_root) |root| {
                            const click = self.interaction.handleClick(root, event.x, event.y - toolbar_height, self.scroll.scroll_y);
                            if (click.target_node) |target| {
                                if (target.node_type == .element and (target.tag == .input or target.tag == .textarea)) {
                                    // Focus input — do NOT navigate
                                    var focus_node: *dom.Node = @constCast(target);

                                    // If we clicked a non-text input (like a button), try to find a companion text input in the same form
                                    if (target.tag == .input) {
                                        const t_type = target.getAttribute("type") orelse "text";
                                        if (std.mem.eql(u8, t_type, "submit") or std.mem.eql(u8, t_type, "hidden")) {
                                            // Search siblings/parent for a text input
                                            var form_root: ?*dom.Node = target.parent;
                                            while (form_root) |fr| {
                                                if (fr.tag == .form) break;
                                                form_root = fr.parent;
                                            }

                                            if (form_root) |fr| {
                                                const Helper = struct {
                                                    fn findTextInput(n: *dom.Node) ?*dom.Node {
                                                        if (n.tag == .input) {
                                                            const it = n.getAttribute("type") orelse "text";
                                                            if (std.mem.eql(u8, it, "text") or std.mem.eql(u8, it, "search")) return n;
                                                        } else if (n.tag == .textarea) return n;
                                                        for (n.children.items) |child| {
                                                            if (findTextInput(child)) |found| return found;
                                                        }
                                                        return null;
                                                    }
                                                };
                                                if (Helper.findTextInput(fr)) |found| {
                                                    focus_node = found;
                                                }
                                            }
                                        }
                                    }
                                    self.input_manager.focus(focus_node);
                                } else {
                                    self.input_manager.blur();

                                    // Task 5: If we hit a container inside a form (and not a link), try to find the primary input
                                    if (click.href == null) {
                                        var form_root: ?*dom.Node = @constCast(target).parent;
                                        while (form_root) |fr| {
                                            if (fr.tag == .form) break;
                                            form_root = fr.parent;
                                        }
                                        if (form_root) |fr| {
                                            const Helper = struct {
                                                fn findTextInput(n: *dom.Node) ?*dom.Node {
                                                    if (n.tag == .input) {
                                                        const it = n.getAttribute("type") orelse "text";
                                                        if (std.mem.eql(u8, it, "text") or std.mem.eql(u8, it, "search")) return n;
                                                    } else if (n.tag == .textarea) return n;
                                                    for (n.children.items) |child| if (findTextInput(child)) |found| return found;
                                                    return null;
                                                }
                                            };
                                            if (Helper.findTextInput(fr)) |found| {
                                                self.input_manager.focus(found);
                                            }
                                        }
                                    }

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
                    }
                },
                .key_down => {
                    var handled = false;
                    if (self.url_bar_focused) {
                        handled = true;
                        if (event.keycode == 51) {
                            if (self.url_bar_len > 0) self.url_bar_len -= 1;
                        } else {
                            var text_len: usize = 0;
                            while (text_len < 8 and event.text[text_len] != 0) : (text_len += 1) {}
                            if (text_len > 0) {
                                const slice = event.text[0..text_len];
                                if (std.mem.indexOfScalar(u8, slice, '\r') != null or std.mem.indexOfScalar(u8, slice, '\n') != null) {
                                    self.url_bar_focused = false;
                                    self.queueNavigation(self.url_bar_text[0..self.url_bar_len]);
                                } else {
                                    for (slice) |c| {
                                        if (c >= 32 and c < 127 and self.url_bar_len < self.url_bar_text.len) {
                                            self.url_bar_text[self.url_bar_len] = c;
                                            self.url_bar_len += 1;
                                        }
                                    }
                                }
                            }
                        }
                    } else if (self.allocator) |alloc| {
                        const input_res = self.input_manager.handleEvent(alloc, event) catch .ignored;
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
                                const content_height = if (window_height > toolbar_height) window_height - toolbar_height else 0;
                                const ctx = layout_mod.LayoutContext{
                                    .allocator = alloc,
                                    .viewport_width = window_width, // Could also get actual viewport
                                    .viewport_height = content_height,
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
                        if (event.modifiers & events.MOD_COMMAND != 0) {
                            if (event.keycode == 33) { // [
                                self.goBack();
                                handled = true;
                            } else if (event.keycode == 30) { // ]
                                self.goForward();
                                handled = true;
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
                            const adj_height = if (event.height > toolbar_height) event.height - toolbar_height else 0;
                            const ctx = layout_mod.LayoutContext{
                                .allocator = alloc,
                                .viewport_width = event.width,
                                .viewport_height = adj_height,
                            };
                            layout_mod.layoutTree(root, ctx);
                            if (self.owned_display_list) |*old_dl| {
                                old_dl.deinit();
                            }
                            self.owned_display_list = display_list_mod.buildDisplayList(alloc, root, self.input_manager.focused_node) catch null;
                            self.scroll.setViewportHeight(adj_height);
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
        const ui_cfg = config.getConfig().ui;
        const toolbar_cfg = ui_cfg.toolbar;
        const scrollbar_cfg = ui_cfg.scrollbar;
        const colors = ui_cfg.colors;
        const toolbar_height = toolbar_cfg.height;

        self.scroll.tick();
        self.processEvents();

        // Process pending navigation
        if (self.pending_url_len > 0) {
            const url_copy = self.pending_url[0..self.pending_url_len];
            std.debug.print("Navigating to: {s}\n", .{url_copy});
            self.navigateTo(url_copy, self.pending_is_history);
            self.pending_url_len = 0;
            self.pending_is_history = false;
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

        // Poll async resources
        if (self.resource_loader) |*rl| {
            if (rl.poll() catch null) |newly_loaded| {
                if (newly_loaded.len > 0) {
                    var needs_rebuild = false;
                    for (newly_loaded) |res| {
                        if (res.type == .CSS) {
                            std.debug.print("[async] Applying CSS: {s}\n", .{res.url});
                            if (self.allocator) |alloc| {
                                const sheet = css.parser.Parser.parse(alloc, res.body) catch continue;
                                self.stylesheets.append(alloc, sheet) catch {};
                                needs_rebuild = true;
                            }
                        } else if (res.type == .JS) {
                            std.debug.print("[async] Executing JS: {s}\n", .{res.url});
                            if (self.js_ctx) |js_ctx| {
                                _ = js_ctx.evaluateScript(res.body);
                                if (js_ctx.hasException()) {
                                    self.logJsException(res.url, res.body);
                                }
                                needs_rebuild = true;
                            }
                        } else if (res.type == .Image) {
                            var fw: c_int = 0;
                            var fh: c_int = 0;
                            if (objc.decode_image_to_texture(self.device, self.command_queue, res.body.ptr, @intCast(res.body.len), &fw, &fh)) |tex| {
                                self.registerImageResource(res.url, tex, @floatFromInt(fw), @floatFromInt(fh));
                                needs_rebuild = true;
                            } else {
                                std.debug.print("[async] Failed to decode image: {s}\n", .{res.url});
                            }
                        } else if (res.type == .Favicon) {
                            std.debug.print("[async] Loaded Favicon: {s}\n", .{res.url});
                            var fw: c_int = 0;
                            var fh: c_int = 0;
                            if (objc.decode_image_to_texture(self.device, self.command_queue, res.body.ptr, @intCast(res.body.len), &fw, &fh)) |tex| {
                                self.favicon_texture = tex;
                            }
                        }
                    }
                    if (needs_rebuild) {
                        self.rebuildRenderTree();
                    }
                }
            }
        }

        const view = self.view orelse return;

        const frame_context = objc.begin_frame(self.command_queue, view);
        if (frame_context) |fc| {
            var frame_width: f32 = 0;
            var frame_height: f32 = 0;
            objc.get_drawable_size(view, &frame_width, &frame_height);
            const content_height = if (frame_height > toolbar_height) frame_height - toolbar_height else 0;
            self.scroll.setViewportHeight(content_height);

            if (self.owned_display_list) |*dl| {
                if (self.pipeline_state) |ps| {
                    if (self.text_renderer) |*tr| {
                        const comp = compositor.Compositor{
                            .rect_pipeline = ps,
                            .text_renderer = tr,
                            .image_pipeline = self.image_pipeline,
                            .device = self.device,
                            .command_queue = self.command_queue,
                            .allocator = self.allocator,
                            .svg_cache = &self.svg_cache,
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

            var width: f32 = 0;
            var height: f32 = 0;
            objc.get_drawable_size(view, &width, &height);

            // Reset scissor to full drawable before toolbar drawing
            objc.reset_scissor_rect(fc, width, height);

            // Render URL Bar on top
            if (self.pipeline_state) |ps| {
                objc.set_pipeline(fc, ps);
                objc.set_projection(fc, width, height);
                const toolbar_bg = colors.toolbar_bg;
                objc.draw_solid_rect(fc, 0, 0, width, toolbar_height, toolbar_bg[0], toolbar_bg[1], toolbar_bg[2], toolbar_bg[3]);

                if (toolbar_cfg.border_height > 0) {
                    const border = colors.toolbar_border;
                    objc.draw_solid_rect(fc, 0, toolbar_height - toolbar_cfg.border_height, width, toolbar_cfg.border_height, border[0], border[1], border[2], border[3]);
                }

                const btn_size = toolbar_cfg.button_size;
                const btn_gap = toolbar_cfg.button_gap;
                const btn_y = @max(0.0, (toolbar_height - btn_size) * 0.5);

                const back_x = toolbar_cfg.padding_x;
                const fwd_x = back_x + btn_size + btn_gap;
                const reload_x = fwd_x + btn_size + btn_gap;

                const address_x = reload_x + btn_size + toolbar_cfg.address_gap;
                const address_w = if (width > address_x + toolbar_cfg.padding_x) width - address_x - toolbar_cfg.padding_x else 0.0;
                const address_h = @min(toolbar_cfg.address_height, toolbar_height);
                const address_y = (toolbar_height - address_h) * 0.5;

                const back_enabled = self.history_pos > 1;
                const fwd_enabled = self.history_pos < self.history_count;
                const reload_enabled = self.history_pos > 0;

                const mouse_in_toolbar = self.mouse_y < toolbar_height;
                const back_hover = mouse_in_toolbar and self.mouse_x >= back_x and self.mouse_x < back_x + btn_size and self.mouse_y >= btn_y and self.mouse_y < btn_y + btn_size;
                const fwd_hover = mouse_in_toolbar and self.mouse_x >= fwd_x and self.mouse_x < fwd_x + btn_size and self.mouse_y >= btn_y and self.mouse_y < btn_y + btn_size;
                const reload_hover = mouse_in_toolbar and self.mouse_x >= reload_x and self.mouse_x < reload_x + btn_size and self.mouse_y >= btn_y and self.mouse_y < btn_y + btn_size;

                const button_bg = colors.button_bg;
                const button_hover_bg = colors.button_hover_bg;
                const button_disabled_bg = colors.button_disabled_bg;

                const back_color = if (back_enabled) (if (back_hover) button_hover_bg else button_bg) else button_disabled_bg;
                const fwd_color = if (fwd_enabled) (if (fwd_hover) button_hover_bg else button_bg) else button_disabled_bg;
                const reload_color = if (reload_enabled) (if (reload_hover) button_hover_bg else button_bg) else button_disabled_bg;

                objc.draw_solid_rect(fc, back_x, btn_y, btn_size, btn_size, back_color[0], back_color[1], back_color[2], back_color[3]);
                objc.draw_solid_rect(fc, fwd_x, btn_y, btn_size, btn_size, fwd_color[0], fwd_color[1], fwd_color[2], fwd_color[3]);
                objc.draw_solid_rect(fc, reload_x, btn_y, btn_size, btn_size, reload_color[0], reload_color[1], reload_color[2], reload_color[3]);

                if (address_w > 0 and address_h > 0) {
                    const address_border = if (self.url_bar_focused) colors.address_focus_border else colors.address_border;
                    objc.draw_solid_rect(fc, address_x, address_y, address_w, address_h, address_border[0], address_border[1], address_border[2], address_border[3]);
                    const border_w = toolbar_cfg.address_border_width;
                    const inner_x = address_x + border_w;
                    const inner_y = address_y + border_w;
                    const inner_w = @max(0.0, address_w - 2.0 * border_w);
                    const inner_h = @max(0.0, address_h - 2.0 * border_w);
                    const address_bg = colors.address_bg;
                    objc.draw_solid_rect(fc, inner_x, inner_y, inner_w, inner_h, address_bg[0], address_bg[1], address_bg[2], address_bg[3]);
                }

                if (self.text_renderer) |*tr| {
                    const app_mod = @import("../platform/app.zig");
                    app_mod.objc.set_pipeline(fc, tr.text_pipeline);

                    const icon_size = toolbar_cfg.url_text_size;
                    const icon_y = textBaseline(tr, btn_y, btn_size, icon_size);
                    const icon_x_offset = (btn_size - icon_size) * 0.5;

                    const icon_enabled = colors.button_icon;
                    const icon_disabled = colors.button_icon_disabled;

                    const back_icon = if (back_enabled) icon_enabled else icon_disabled;
                    const fwd_icon = if (fwd_enabled) icon_enabled else icon_disabled;
                    const reload_icon = if (reload_enabled) icon_enabled else icon_disabled;

                    tr.drawTextScaled(fc, "<", back_x + icon_x_offset, icon_y, icon_size, back_icon[0], back_icon[1], back_icon[2], back_icon[3]);
                    tr.drawTextScaled(fc, ">", fwd_x + icon_x_offset, icon_y, icon_size, fwd_icon[0], fwd_icon[1], fwd_icon[2], fwd_icon[3]);
                    tr.drawTextScaled(fc, "R", reload_x + icon_x_offset, icon_y, icon_size, reload_icon[0], reload_icon[1], reload_icon[2], reload_icon[3]);

                    var url_x_offset: f32 = address_x + toolbar_cfg.address_padding_x;
                    if (self.favicon_texture) |fav_tex| {
                        if (self.image_pipeline) |ip| {
                            objc.set_pipeline(fc, ip);
                            const fav_size: f32 = toolbar_cfg.favicon_size;
                            const fav_y: f32 = address_y + (address_h - fav_size) * 0.5;
                            const vertices = [6][8]f32{
                                .{ url_x_offset, fav_y, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ url_x_offset + fav_size, fav_y, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ url_x_offset, fav_y + fav_size, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ url_x_offset + fav_size, fav_y, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ url_x_offset, fav_y + fav_size, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
                                .{ url_x_offset + fav_size, fav_y + fav_size, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
                            };
                            objc.batch_image_quads(fc, self.device, fav_tex, @ptrCast(&vertices), 6);
                            url_x_offset += fav_size + toolbar_cfg.favicon_gap;
                        }
                    }

                    app_mod.objc.set_pipeline(fc, tr.text_pipeline);
                    const url_text_size = toolbar_cfg.url_text_size;
                    const url_text_y = textBaseline(tr, address_y, address_h, url_text_size);
                    const url_to_draw = if (self.url_bar_len > 0) self.url_bar_text[0..self.url_bar_len] else "Enter URL...";
                    const url_color = if (self.url_bar_len > 0) colors.url_text else colors.url_placeholder;

                    const title_width = if (self.page_title_len > 0) toolbar_cfg.title_area_width else 0.0;
                    const url_clip_w = @max(0.0, address_w - (toolbar_cfg.address_padding_x * 2.0) - title_width);
                    if (url_clip_w > 0) {
                        objc.set_scissor_rect(fc, url_x_offset, address_y, url_clip_w, address_h, height);
                        tr.drawTextScaled(fc, url_to_draw, url_x_offset, url_text_y, url_text_size, url_color[0], url_color[1], url_color[2], url_color[3]);
                    }

                    if (self.page_title_len > 0 and title_width > 0.0) {
                        const title_text = self.page_title[0..self.page_title_len];
                        const title_size = toolbar_cfg.title_text_size;
                        const title_y = textBaseline(tr, address_y, address_h, title_size);
                        const title_x = address_x + address_w - title_width + toolbar_cfg.address_padding_x;
                        const title_clip_w = @max(0.0, title_width - toolbar_cfg.address_padding_x);
                        if (title_clip_w > 0) {
                            const title_color = colors.title_text;
                            objc.set_scissor_rect(fc, title_x, address_y, title_clip_w, address_h, height);
                            tr.drawTextScaled(fc, title_text, title_x, title_y, title_size, title_color[0], title_color[1], title_color[2], title_color[3]);
                        }
                    }

                    objc.reset_scissor_rect(fc, width, height);
                }

                // Loading Bar
                var is_loading = false;
                if (self.resource_loader) |rl| {
                    if (rl.pending.items.len > 0) {
                        is_loading = true;
                        self.loading_animation_time += 0.04;
                        if (self.loading_animation_time > std.math.pi * 2.0) {
                            self.loading_animation_time -= std.math.pi * 2.0;
                        }
                    } else {
                        self.loading_animation_time = 0.0;
                    }
                }

                if (is_loading) {
                    objc.set_pipeline(fc, ps);
                    const sine_wave = (std.math.sin(self.loading_animation_time) + 1.0) / 2.0; // 0 to 1
                    const bar_width = width * toolbar_cfg.loading_bar_width_ratio;
                    const bar_x = sine_wave * (width - bar_width);
                    const bar_y = toolbar_height - toolbar_cfg.loading_bar_offset - toolbar_cfg.loading_bar_height;
                    const loading = colors.loading_bar;
                    objc.draw_solid_rect(fc, bar_x, bar_y, bar_width, toolbar_cfg.loading_bar_height, loading[0], loading[1], loading[2], loading[3]);
                }

                // Render Scrollbar
                objc.set_pipeline(fc, ps);
                if (self.scroll.content_height > self.scroll.viewport_height) {
                    const track_height = height - toolbar_height;
                    const thumb_height = @max(scrollbar_cfg.min_thumb_height, (self.scroll.viewport_height / self.scroll.content_height) * track_height);
                    const max_scroll = self.scroll.content_height - self.scroll.viewport_height;
                    const scroll_progress = if (max_scroll > 0) self.scroll.scroll_y / max_scroll else 0.0;
                    const thumb_y = toolbar_height + scroll_progress * (track_height - thumb_height);
                    const track = colors.scrollbar_track;
                    const thumb = colors.scrollbar_thumb;
                    const track_x = width - scrollbar_cfg.width;
                    const thumb_x = track_x + scrollbar_cfg.thumb_inset;
                    const thumb_w = @max(1.0, scrollbar_cfg.width - 2.0 * scrollbar_cfg.thumb_inset);
                    objc.draw_solid_rect(fc, track_x, toolbar_height, scrollbar_cfg.width, track_height, track[0], track[1], track[2], track[3]);
                    objc.draw_solid_rect(fc, thumb_x, thumb_y, thumb_w, thumb_height, thumb[0], thumb[1], thumb[2], thumb[3]);
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
        const new_styled = resolver.resolve(doc.root, self.stylesheets.items) catch |err| {
            std.debug.print("rebuildRenderTree: style resolver failed: {}\n", .{err});
            return;
        };
        if (new_styled == null) {
            std.debug.print("rebuildRenderTree: style resolver returned null (possibly display: none on root)\n", .{});
        }
        self.styled_root = new_styled;

        if (new_styled) |ns| {
            self.queueBackgroundImageLoads(ns);
            const toolbar_height = config.getConfig().ui.toolbar.height;

            const new_layout = layout_mod.buildLayoutTree(alloc, ns) catch |err| {
                std.debug.print("rebuildRenderTree: buildLayoutTree failed: {}\n", .{err});
                return;
            };

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
                .viewport_height = if (vh > toolbar_height) vh - toolbar_height else 0,
            };
            layout_mod.layoutTree(new_layout, lctx);
            self.attachCachedImages(new_layout);

            const new_dl = display_list_mod.buildDisplayList(alloc, new_layout, self.input_manager.focused_node) catch |err| {
                std.debug.print("rebuildRenderTree: buildDisplayList failed: {}\n", .{err});
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
        } else {
            if (self.layout_root) |old_root| {
                if (self.owned_display_list) |*old_dl| {
                    old_dl.deinit();
                }
                old_root.deinit(alloc);
                alloc.destroy(old_root);
                self.layout_root = null;
                self.owned_display_list = null;
            }
            self.scroll.setContentHeight(0);
        }
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

    fn navigateTo(self: *Renderer, url_str: []const u8, is_history: bool) void {
        const alloc = self.allocator orelse return;
        var nav = self.nav_ctx orelse return;

        if (!is_history) {
            if (self.history_pos < self.history_count) {
                self.history_count = self.history_pos;
            }
            if (self.history_count < 64) {
                const len = @min(url_str.len, 4096);
                @memcpy(self.history[self.history_count][0..len], url_str[0..len]);
                self.history_len[self.history_count] = len;
                self.history_count += 1;
                self.history_pos = self.history_count;
            } else {
                for (1..64) |i| {
                    @memcpy(self.history[i - 1][0..self.history_len[i]], self.history[i][0..self.history_len[i]]);
                    self.history_len[i - 1] = self.history_len[i];
                }
                const len = @min(url_str.len, 4096);
                @memcpy(self.history[63][0..len], url_str[0..len]);
                self.history_len[63] = len;
            }
        }

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

        // 2. Update base URL (prefer final URL after redirects)
        if (resp.final_url) |final_url| {
            const owned = alloc.dupe(u8, final_url) catch null;
            if (owned) |owned_buf| {
                if (net.url.Url.parse(owned_buf)) |parsed| {
                    if (self.base_url_storage) |old| alloc.free(old);
                    self.base_url_storage = owned_buf;
                    nav.base_url = parsed;
                } else |_| {
                    alloc.free(owned_buf);
                }
            }
        } else {
            nav.base_url = net.url.Url.parse(url_str) catch nav.base_url;
        }
        self.nav_ctx = nav;

        const len = @min(url_str.len, self.url_bar_text.len);
        @memcpy(self.url_bar_text[0..len], url_str[0..len]);
        self.url_bar_len = len;

        // 3. Parse HTML
        std.debug.print("Parsing HTML ({d} bytes)...\n", .{resp.body.len});
        const new_doc = dom.builder.parseHTML(alloc, resp.body) catch |err| {
            std.debug.print("HTML Parse failed: {}\n", .{err});
            alloc.free(resp.body);
            if (resp.final_url) |u| alloc.free(u);
            return;
        };
        alloc.free(resp.body);
        if (resp.final_url) |u| alloc.free(u);
        std.debug.print("HTML Parse successful, building render tree...\n", .{});
        self.clearImageCache();
        self.favicon_texture = null;

        if (self.js_ctx) |js_ctx| {
            js.document_global.updateDocument(new_doc);
            const inline_scripts_opt = js.script_runner.extractScripts(alloc, new_doc.root) catch null;
            if (inline_scripts_opt) |inline_scripts| {
                defer js.script_runner.freeScripts(alloc, inline_scripts);
                js.script_runner.executeScripts(js_ctx, inline_scripts);
            }
        }

        var title_found = false;
        if (self.findTitleNode(new_doc.root)) |title_node| {
            if (title_node.children.items.len > 0) {
                const text_child = title_node.children.items[0];
                if (text_child.node_type == .text) {
                    if (text_child.data) |title_text| {
                        const title_len = @min(title_text.len, 1023);
                        @memcpy(self.page_title[0..title_len], title_text[0..title_len]);
                        self.page_title[title_len] = 0;
                        self.page_title_len = title_len;
                        title_found = true;

                        const app_mod = @import("../platform/app.zig");
                        if (self.window) |w| {
                            app_mod.objc.set_window_title(w, @ptrCast(&self.page_title));
                        }
                    }
                }
            }
        }

        if (!title_found) {
            const fallback = "Metal Browser Engine";
            @memcpy(self.page_title[0..fallback.len], fallback);
            self.page_title[fallback.len] = 0;
            self.page_title_len = fallback.len;

            const app_mod = @import("../platform/app.zig");
            if (self.window) |w| {
                app_mod.objc.set_window_title(w, @ptrCast(&self.page_title));
            }
        }

        // 4. Discover and async load sub-resources
        if (self.resource_loader) |*rl| {
            rl.deinit();
        }
        self.resource_loader = net.loader.ResourceLoader.init(alloc, nav.fetch_client, nav.base_url);

        const refs = self.resource_loader.?.discoverResources(new_doc.root) catch &[_]net.loader.ResourceRef{};

        // Cap async loading at 100 resources for now to prevent overwhelming
        const max_resources = @min(refs.len, 100);
        const limited_refs = refs[0..max_resources];

        self.resource_loader.?.startLoading(limited_refs) catch |err| {
            std.debug.print("Failed to start loading resources: {}\n", .{err});
        };

        if (refs.len > 0) {
            std.debug.print("[nav] Discovered {d} sub-resources, loading up to {d} asynchronously\n", .{ refs.len, max_resources });
        }

        // 5. Build initial stylesheets (UA + inline)
        const ua_sheet = css.user_agent.getStylesheet(alloc) catch return;
        const page_sheets = css.style_extract.extractStylesheets(alloc, new_doc.root) catch &[_]css.Stylesheet{};

        self.stylesheets.clearRetainingCapacity();
        self.stylesheets.append(alloc, ua_sheet) catch return;
        self.stylesheets.appendSlice(alloc, page_sheets) catch {};

        // 6. Free old state
        if (self.document) |old_doc| {
            old_doc.deinit();
        }

        // 7. Update renderer state
        self.document = new_doc;

        // 8. Rebuild initial render tree
        self.rebuildRenderTree();
        self.scroll.setScrollY(0);

        // Cleanup temporary refs
        for (refs) |ref| alloc.free(ref.url);
        alloc.free(refs);

        std.debug.print("Initial Navigation complete\n", .{});
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
                            // Skip buttons and other non-data inputs
                            const i_type = n.getAttribute("type") orelse "text";
                            if (std.mem.eql(u8, i_type, "submit") or
                                std.mem.eql(u8, i_type, "button") or
                                std.mem.eql(u8, i_type, "image") or
                                std.mem.eql(u8, i_type, "reset") or
                                std.mem.eql(u8, i_type, "hidden") and n.attributes.items.len == 0 // placeholder check
                            ) {
                                // For now skip hidden too if they look like artifacts,
                                // though real hidden inputs SHOULD be included.
                                // But let's at least skip buttons.
                                if (!std.mem.eql(u8, i_type, "hidden")) {
                                    for (n.children.items) |child| try collectInputs(alloc2, child, q);
                                    return;
                                }
                            }

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
            const action_trimmed = std.mem.trim(u8, action, " \t\n\r");
            url_str.appendSlice(alloc, action_trimmed) catch return;
            if (query.items.len > 0) {
                if (std.mem.indexOfScalar(u8, action_trimmed, '?') == null) {
                    url_str.append(alloc, '?') catch return;
                } else if (!std.mem.endsWith(u8, action_trimmed, "&") and !std.mem.endsWith(u8, action_trimmed, "?")) {
                    url_str.append(alloc, '&') catch return;
                }
                url_str.appendSlice(alloc, query.items) catch return;
            }

            std.debug.print("Submitting form to: {s}\n", .{url_str.items});
            self.queueNavigation(url_str.items);
        }
    }
};
