const std = @import("std");
const app = @import("platform/app.zig");
const window = @import("platform/window.zig");
const renderer = @import("render/renderer.zig");
const events = @import("platform/events.zig");
const config = @import("config.zig");
const dom = @import("dom/mod.zig");
const css = @import("css/mod.zig");
const layout = @import("layout/mod.zig");
const display_list = @import("render/display_list.zig");
const js = @import("js/mod.zig");
const net = @import("net/mod.zig");
const jsc = @cImport({
    @cInclude("jsc_bridge.h");
    @cInclude("net_bridge.h");
    @cInclude("image_bridge.h");
});

const default_html =
    \\<html>
    \\<body style="background-color: #1a1a2e; padding: 20px;">
    \\  <div style="background-color: #16213e; padding: 16px; margin-bottom: 12px;">
    \\    <p style="color: #e94560;">Metal Browser Engine</p>
    \\  </div>
    \\  <div style="background-color: #0f3460; padding: 16px;">
    \\    <p style="color: #eeeeee;">Phase 6 - File Loading Active</p>
    \\  </div>
    \\</body>
    \\</html>
;

const bw = struct {
    fn ctxCreate() ?*anyopaque {
        return jsc.jsc_context_create();
    }
    fn ctxRelease(c: ?*anyopaque) void {
        jsc.jsc_context_release(c);
    }
    fn eval(c: ?*anyopaque, s: [*]const u8, n: c_int) ?*anyopaque {
        return jsc.jsc_evaluate_script(c, s, n);
    }
    fn global(c: ?*anyopaque) ?*anyopaque {
        return jsc.jsc_global_object(c);
    }
    fn makeObj(c: ?*anyopaque) ?*anyopaque {
        return jsc.jsc_make_object(c);
    }
    fn setProp(c: ?*anyopaque, o: ?*anyopaque, nm: [*:0]const u8, v: ?*anyopaque) void {
        jsc.jsc_object_set_property(c, o, nm, v);
    }
    fn makeFn(c: ?*anyopaque, nm: [*:0]const u8, cb: ?*const anyopaque) ?*anyopaque {
        return jsc.jsc_make_function(c, nm, @ptrCast(@alignCast(cb)));
    }
    fn makeStr(c: ?*anyopaque, s: [*:0]const u8) ?*anyopaque {
        return jsc.jsc_make_string_value(c, s);
    }
    fn makeUndef(c: ?*anyopaque) ?*anyopaque {
        return jsc.jsc_make_undefined(c);
    }
    fn valToStr(c: ?*anyopaque, v: ?*anyopaque) ?*anyopaque {
        return jsc.jsc_value_to_string(c, v);
    }
    fn strUtf8(s: ?*anyopaque, b: [*]u8, sz: c_int) c_int {
        return jsc.jsc_string_get_utf8(s, b, sz);
    }
    fn strRelease(s: ?*anyopaque) void {
        jsc.jsc_string_release(s);
    }
    fn isStr(c: ?*anyopaque, v: ?*anyopaque) c_int {
        return jsc.jsc_value_is_string(c, v);
    }
    fn valueProtect(c: ?*anyopaque, v: ?*anyopaque) void {
        jsc.jsc_value_protect(c, v);
    }
    fn valueUnprotect(c: ?*anyopaque, v: ?*anyopaque) void {
        jsc.jsc_value_unprotect(c, v);
    }
    fn makeClassInstance(c: ?*anyopaque, pd: ?*anyopaque, get_cb: ?*const anyopaque, set_cb: ?*const anyopaque) ?*anyopaque {
        return jsc.jsc_make_class_instance(c, pd, @ptrCast(@alignCast(get_cb)), @ptrCast(@alignCast(set_cb)));
    }
    fn objectGetPrivate(o: ?*anyopaque) ?*anyopaque {
        return jsc.jsc_object_get_private(o);
    }
    fn objectGetProperty(c: ?*anyopaque, o: ?*anyopaque, n: [*:0]const u8) ?*anyopaque {
        return jsc.jsc_object_get_property(c, o, n);
    }
    fn makeNumberValue(c: ?*anyopaque, v: f64) ?*anyopaque {
        return jsc.jsc_make_number_value(c, v);
    }
    fn valueToNumber(c: ?*anyopaque, v: ?*anyopaque) f64 {
        return jsc.jsc_value_to_number(c, v);
    }
    fn valueIsNumber(c: ?*anyopaque, v: ?*anyopaque) c_int {
        return jsc.jsc_value_is_number(c, v);
    }
    fn makeNull(c: ?*anyopaque) ?*anyopaque {
        return jsc.jsc_make_null(c);
    }
    fn callFunction(c: ?*anyopaque, f: ?*anyopaque, t: ?*anyopaque, n: c_int, a: ?[*]const ?*anyopaque) ?*anyopaque {
        return jsc.jsc_call_function(c, f, t, n, a);
    }
    fn classGetUserData(o: ?*anyopaque) ?*anyopaque {
        return jsc.jsc_class_get_user_data(o);
    }
    fn hasException(c: ?*anyopaque) c_int {
        return jsc.jsc_has_exception(c);
    }
};

const jsc_bridge = js.context.JsBridge{ .context_create = &bw.ctxCreate, .context_release = &bw.ctxRelease, .evaluate_script = &bw.eval, .global_object = &bw.global, .make_object = &bw.makeObj, .object_set_property = &bw.setProp, .make_function = &bw.makeFn, .make_string_value = &bw.makeStr, .make_undefined = &bw.makeUndef, .value_to_string = &bw.valToStr, .string_get_utf8 = &bw.strUtf8, .string_release = &bw.strRelease, .value_is_string = &bw.isStr, .value_protect = &bw.valueProtect, .value_unprotect = &bw.valueUnprotect, .make_class_instance = &bw.makeClassInstance, .object_get_private = &bw.objectGetPrivate, .object_get_property = &bw.objectGetProperty, .make_number_value = &bw.makeNumberValue, .value_to_number = &bw.valueToNumber, .value_is_number = &bw.valueIsNumber, .make_null = &bw.makeNull, .call_function = &bw.callFunction, .class_get_user_data = &bw.classGetUserData, .has_exception = &bw.hasException };

fn jsConsolePrint(
    ctx_handle: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
    prefix: []const u8,
) ?*anyopaque {
    if (arg_count > 0) {
        if (args) |arg_ptr| {
            for (arg_ptr[0..@as(usize, @intCast(arg_count))]) |arg| {
                if (arg) |val| {
                    const sr = jsc.jsc_value_to_string(ctx_handle, val) orelse continue;
                    var buf: [1024]u8 = undefined;
                    const len = jsc.jsc_string_get_utf8(sr, &buf, 1024);
                    if (len > 1) std.debug.print("{s}{s}", .{ prefix, buf[0..@as(usize, @intCast(len - 1))] });
                    jsc.jsc_string_release(sr);
                }
            }
            std.debug.print("\n", .{});
        }
    }
    return jsc.jsc_make_undefined(ctx_handle);
}

fn jsConsoleLog(
    ctx_handle: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    return jsConsolePrint(ctx_handle, arg_count, args, "[JS] ");
}

fn jsConsoleWarn(
    ctx_handle: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    return jsConsolePrint(ctx_handle, arg_count, args, "[JS WARN] ");
}

fn jsConsoleError(
    ctx_handle: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    return jsConsolePrint(ctx_handle, arg_count, args, "[JS ERROR] ");
}

var global_renderer: ?*renderer.Renderer = null;

fn atlasMeasure(text_str: []const u8, font_size: f32, font_weight: f32) f32 {
    if (global_renderer) |r| {
        if (r.text_renderer) |text_r| {
            const scale = font_size / text_r.font_size;
            var width: f32 = 0;
            const metrics = if (font_weight >= 700 and text_r.bold_atlas_texture != null) text_r.bold_glyph_metrics else text_r.glyph_metrics;
            for (text_str) |c| {
                if (c < 32 or c > 126) continue;
                const idx = c - 32;
                width += metrics[idx].advance * scale;
            }
            return width;
        }
    }
    return @as(f32, @floatFromInt(text_str.len)) * 8.0;
}

const net_bridge = net.fetch.NetBridge{
    .net_fetch_start = @ptrCast(&struct { fn start(url_arg: [*:0]const u8, method: [*:0]const u8, h1: ?[*]const ?[*:0]const u8, c1: c_int, body: ?[*]const u8, l: c_int) callconv(.c) net.fetch.FetchHandle { return jsc.net_fetch_start(url_arg, method, @ptrCast(@constCast(h1)), c1, body, l); } }.start),
    .net_fetch_poll = @ptrCast(&jsc.net_fetch_poll),
    .net_fetch_get_status_code = @ptrCast(&jsc.net_fetch_get_status_code),
    .net_fetch_get_body = @ptrCast(&struct { fn body(h: net.fetch.FetchHandle, len: *c_int) callconv(.c) ?[*]const u8 { return jsc.net_fetch_get_body(h, len); } }.body),
    .net_fetch_free = @ptrCast(&jsc.net_fetch_free),
    .net_fetch_get_header = @ptrCast(&struct { fn f(h: net.fetch.FetchHandle, n: [*:0]const u8, o: [*]u8, m: c_int) callconv(.c) c_int { return jsc.net_fetch_get_header(h, n, o, m); } }.f),
    .net_fetch_get_header_count = @ptrCast(&jsc.net_fetch_get_header_count),
    .net_fetch_get_header_at = @ptrCast(&struct { fn f(h: net.fetch.FetchHandle, i: c_int, on: [*]u8, nm: c_int, ov: [*]u8, vm: c_int) callconv(.c) c_int { return jsc.net_fetch_get_header_at(h, i, on, nm, ov, vm); } }.f),
};

pub fn main() !void {
    const cfg = config.getConfig();
    const my_app = try app.App.init();
    _ = my_app;

    var my_renderer = try renderer.Renderer.init();
    var my_window = try window.Window.init(cfg.window.title, @floatFromInt(cfg.window.width), @floatFromInt(cfg.window.height));

    const view = try my_window.setMetalView(my_renderer.device);
    my_renderer.view = view;
    app.objc.set_event_callback(view, null, events.eventCallback);
    app.objc.set_metal_delegate(view, &my_renderer, renderer.Renderer.draw);
    my_renderer.setClearColor(cfg.renderer.clear_color);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    var fetch_client = net.fetch.FetchClient.init(allocator, &net_bridge);
    var base_url = net.url.Url.parse("http://localhost/") catch unreachable;

    const html_source = blk: {
        var args = std.process.args();
        _ = args.next();
        if (args.next()) |arg_path| {
            if (std.mem.startsWith(u8, arg_path, "http://") or std.mem.startsWith(u8, arg_path, "https://")) {
                std.debug.print("Fetching URL: {s}\n", .{arg_path});
                base_url = net.url.Url.parse(arg_path) catch base_url;
                
                var resp = fetch_client.fetch(.{ .url = arg_path }) catch |err| {
                    std.debug.print("Failed to fetch page: {}\n", .{err});
                    break :blk @as([]const u8, default_html);
                };

                // Free response headers (we don't need them for the main page)
                for (resp.headers) |hdr| {
                    allocator.free(hdr.name);
                    allocator.free(hdr.value);
                }
                if (resp.headers.len > 0) allocator.free(resp.headers);
                resp.headers = &[_]net.types.HttpHeader{};
                
                if (resp.status_code == 200) {
                    break :blk resp.body;
                } else {
                    resp.deinit(allocator);
                    std.debug.print("HTTP Error: {d}\n", .{resp.status_code});
                    break :blk @as([]const u8, default_html);
                }
            } else {
                const file = std.fs.cwd().openFile(arg_path, .{}) catch |err| {
                    std.debug.print("Failed to open {s}: {}\n", .{ arg_path, err });
                    break :blk @as([]const u8, default_html);
                };
                defer file.close();
                break :blk file.readToEndAlloc(allocator, cfg.parser.max_document_size_bytes) catch |err| {
                    std.debug.print("Failed to read file: {}\n", .{err});
                    break :blk @as([]const u8, default_html);
                };
            }
        }
        break :blk @as([]const u8, default_html);
    };
    defer if (html_source.ptr != default_html.ptr) allocator.free(html_source);

    if (html_source.ptr != default_html.ptr) {
        std.debug.print("Metal Browser Engine -- Loaded from file\n", .{});
    } else {
        std.debug.print("Metal Browser Engine -- Using default HTML\n", .{});
    }

    const document = try dom.builder.parseHTML(allocator, html_source);
    defer document.deinit();

    // --- Resource Loading Pipeline ---
    var resource_loader = net.loader.ResourceLoader.init(allocator, &fetch_client, base_url);
    const refs = resource_loader.discoverResources(document.root) catch &[_]net.loader.ResourceRef{};
    defer {
        for (refs) |ref| allocator.free(ref.url);
        allocator.free(refs);
    }

    if (refs.len > 0) {
        std.debug.print("Discovered {d} sub-resources\n", .{refs.len});
    }

    const loaded_resources = resource_loader.loadResources(refs) catch &[_]net.loader.LoadedResource{};
    defer {
        for (loaded_resources) |*res| {
            @constCast(res).deinit(allocator);
        }
        allocator.free(loaded_resources);
    }

    // --- JS Context ---
    var js_ctx = try js.context.JsContext.init(allocator, &jsc_bridge);
    defer js_ctx.deinit();
    js.console.bindConsole(&js_ctx, @ptrCast(&jsConsoleLog), @ptrCast(&jsConsoleWarn), @ptrCast(&jsConsoleError));

    var js_runtime = js.wiring.JsRuntime.initRuntime(allocator, &js_ctx);
    defer js_runtime.deinit(allocator, &js_ctx);
    try js_runtime.wire(allocator, &js_ctx, document);

    // Execute inline scripts
    const scripts = try js.script_runner.extractScripts(allocator, document.root);
    defer js.script_runner.freeScripts(allocator, scripts);
    js.script_runner.executeScripts(&js_ctx, scripts);

    // --- Apply external resources ---
    // External CSS
    var ext_sheets = std.ArrayListUnmanaged(css.Stylesheet){};
    defer {
        for (ext_sheets.items) |sheet| {
            for (sheet.rules) |rule| {
                for (rule.selectors) |sel| {
                    for (sel.components) |comp| {
                        if (comp.part.tag) |t| allocator.free(t);
                        if (comp.part.id) |id| allocator.free(id);
                        for (comp.part.classes) |c| allocator.free(c);
                        if (comp.part.classes.len > 0) allocator.free(comp.part.classes);
                    }
                    allocator.free(sel.components);
                }
                for (rule.declarations) |decl| {
                    allocator.free(decl.property);
                    allocator.free(decl.value);
                }
                allocator.free(rule.selectors);
                allocator.free(rule.declarations);
            }
            allocator.free(sheet.rules);
        }
        ext_sheets.deinit(allocator);
    }

    for (loaded_resources) |res| {
        switch (res.type) {
            .CSS => {
                std.debug.print("Applying external CSS: {s}\n", .{res.url});
                const sheet = css.parser.Parser.parse(allocator, res.body) catch |err| {
                    std.debug.print("Failed to parse CSS from {s}: {}\n", .{ res.url, err });
                    continue;
                };
                ext_sheets.append(allocator, sheet) catch continue;
            },
            .JS => {
                std.debug.print("Executing external JS: {s}\n", .{res.url});
                _ = js_ctx.evaluateScript(res.body);
            },
            .Image => {
                std.debug.print("Loading image: {s}\n", .{res.url});
                // Store image data for later attachment to layout boxes
            },
        }
    }

    // --- Style resolution ---
    const ua_sheet = try css.user_agent.getStylesheet(allocator);
    const page_sheets = try css.style_extract.extractStylesheets(allocator, document.root);
    defer css.style_extract.freeStylesheets(allocator, page_sheets);
    var all_sheets = std.ArrayListUnmanaged(css.Stylesheet){};
    defer all_sheets.deinit(allocator);
    try all_sheets.append(allocator, ua_sheet);
    for (page_sheets) |s| try all_sheets.append(allocator, s);
    for (ext_sheets.items) |s| try all_sheets.append(allocator, s);

    var resolver = css.resolver.StyleResolver.init(allocator);
    const styled_root = try resolver.resolve(document.root, all_sheets.items);

    global_renderer = &my_renderer;
    layout.text_measure.setMeasureFn(&atlasMeasure);
    const layout_root = try layout.buildLayoutTree(allocator, styled_root);
    const lctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = @floatFromInt(cfg.window.width),
        .viewport_height = @floatFromInt(cfg.window.height),
    };
    layout.layoutTree(layout_root, lctx);

    const dl = try display_list.buildDisplayList(allocator, layout_root);

    my_renderer.setDocument(allocator, layout_root, dl);

    // --- Image texture attachment ---
    // Walk loaded resources and decode images, attaching textures to matching layout boxes
    for (loaded_resources) |res| {
        if (res.kind != .Image) continue;
        var tex_w: c_int = 0;
        var tex_h: c_int = 0;
        const texture = jsc.decode_image_to_texture(
            my_renderer.device,
            my_renderer.command_queue,
            @ptrCast(res.body.ptr),
            @intCast(@as(i64, @intCast(res.body.len))),
            &tex_w,
            &tex_h,
        );
        if (texture) |tex| {
            std.debug.print("Decoded image {s}: {d}x{d}\n", .{ res.url, tex_w, tex_h });
            attachImageToLayoutTree(layout_root, res.url, tex, @floatFromInt(tex_w), @floatFromInt(tex_h));
        } else {
            std.debug.print("Failed to decode image: {s}\n", .{res.url});
        }
    }
    my_renderer.setFrameContext(.{
        .timer_queue = &js_runtime.timer_queue,
        .raf_queue = &js_runtime.raf_queue,
        .event_dispatcher = &js_runtime.event_dispatcher,
        .pipeline_state = &js_runtime.pipeline_state,
    });
    my_renderer.setRenderContext(document, all_sheets.items);
    my_renderer.styled_root = styled_root;
    my_renderer.nav_ctx = .{
        .fetch_client = &fetch_client,
        .base_url = base_url,
        .js_bridge = &jsc_bridge,
    };

    std.debug.print("Metal Browser Engine -- Version 0.1.0-draft\n", .{});
    app.objc.run_application();
}

fn attachImageToLayoutTree(box: *layout.LayoutBox, url: []const u8, texture: *anyopaque, w: f32, h: f32) void {
    if (box.styled_node) |sn| {
        if (sn.node.node_type == .element) {
            if (sn.node.tag == .img) {
                if (sn.node.getAttribute("src")) |src| {
                    // Check if the src matches (could be relative or absolute)
                    if (std.mem.eql(u8, src, url) or std.mem.endsWith(u8, url, src)) {
                        box.image_texture = texture;
                        box.intrinsic_width = w;
                        box.intrinsic_height = h;
                        // Set box dimensions if not already set by CSS
                        if (box.dimensions.content.width == 0) {
                            box.dimensions.content.width = w;
                        }
                        if (box.dimensions.content.height == 0) {
                            box.dimensions.content.height = h;
                        }
                        return;
                    }
                }
            }
        }
    }
    for (box.children.items) |child| {
        attachImageToLayoutTree(child, url, texture, w, h);
    }
}
