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
const jsc = @cImport({
    @cInclude("jsc_bridge.h");
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
    fn ctxCreate() ?*anyopaque { return jsc.jsc_context_create(); }
    fn ctxRelease(c: ?*anyopaque) void { jsc.jsc_context_release(c); }
    fn eval(c: ?*anyopaque, s: [*]const u8, n: c_int) ?*anyopaque {
        return jsc.jsc_evaluate_script(c, s, n);
    }
    fn global(c: ?*anyopaque) ?*anyopaque { return jsc.jsc_global_object(c); }
    fn makeObj(c: ?*anyopaque) ?*anyopaque { return jsc.jsc_make_object(c); }
    fn setProp(c: ?*anyopaque, o: ?*anyopaque, nm: [*:0]const u8, v: ?*anyopaque) void {
        jsc.jsc_object_set_property(c, o, nm, v);
    }
    fn makeFn(c: ?*anyopaque, nm: [*:0]const u8, cb: ?*const anyopaque) ?*anyopaque {
        return jsc.jsc_make_function(c, nm, @ptrCast(@alignCast(cb)));
    }
    fn makeStr(c: ?*anyopaque, s: [*:0]const u8) ?*anyopaque {
        return jsc.jsc_make_string_value(c, s);
    }
    fn makeUndef(c: ?*anyopaque) ?*anyopaque { return jsc.jsc_make_undefined(c); }
    fn valToStr(c: ?*anyopaque, v: ?*anyopaque) ?*anyopaque {
        return jsc.jsc_value_to_string(c, v);
    }
    fn strUtf8(s: ?*anyopaque, b: [*]u8, sz: c_int) c_int {
        return jsc.jsc_string_get_utf8(s, b, sz);
    }
    fn strRelease(s: ?*anyopaque) void { jsc.jsc_string_release(s); }
    fn isStr(c: ?*anyopaque, v: ?*anyopaque) c_int { return jsc.jsc_value_is_string(c, v); }
};

const jsc_bridge = js.context.JsBridge{ .context_create = &bw.ctxCreate, .context_release = &bw.ctxRelease, .evaluate_script = &bw.eval, .global_object = &bw.global, .make_object = &bw.makeObj, .object_set_property = &bw.setProp, .make_function = &bw.makeFn, .make_string_value = &bw.makeStr, .make_undefined = &bw.makeUndef, .value_to_string = &bw.valToStr, .string_get_utf8 = &bw.strUtf8, .string_release = &bw.strRelease, .value_is_string = &bw.isStr };

fn jsConsoleLog(
    ctx_handle: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    if (arg_count > 0) {
        if (args) |arg_ptr| {
            for (arg_ptr[0..@as(usize, @intCast(arg_count))]) |arg| {
                if (arg) |val| {
                    const sr = jsc.jsc_value_to_string(ctx_handle, val) orelse continue;
                    var buf: [1024]u8 = undefined;
                    const len = jsc.jsc_string_get_utf8(sr, &buf, 1024);
                    if (len > 1) std.debug.print("[JS] {s}", .{buf[0..@as(usize, @intCast(len - 1))]});
                    jsc.jsc_string_release(sr);
                }
            }
            std.debug.print("\n", .{});
        }
    }
    return jsc.jsc_make_undefined(ctx_handle);
}

fn coreMeasure(text_str: []const u8, font_size: f32) f32 {
    return app.objc.measure_text_width(text_str.ptr, @intCast(text_str.len), font_size);
}

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
    const html_source = blk: {
        var args = std.process.args();
        _ = args.next();
        if (args.next()) |file_path| {
            const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
                std.debug.print("Failed to open {s}: {}\n", .{ file_path, err });
                break :blk @as([]const u8, default_html);
            };
            defer file.close();
            break :blk file.readToEndAlloc(allocator, cfg.parser.max_document_size_bytes) catch |err| {
                std.debug.print("Failed to read file: {}\n", .{err});
                break :blk @as([]const u8, default_html);
            };
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

    var js_ctx = try js.context.JsContext.init(allocator, &jsc_bridge);
    defer js_ctx.deinit();
    js.console.bindConsole(&js_ctx, @ptrCast(&jsConsoleLog));
    const scripts = try js.script_runner.extractScripts(allocator, document.root);
    defer js.script_runner.freeScripts(allocator, scripts);
    js.script_runner.executeScripts(&js_ctx, scripts);

    const ua_sheet = try css.user_agent.getStylesheet(allocator);
    const page_sheets = try css.style_extract.extractStylesheets(allocator, document.root);
    defer css.style_extract.freeStylesheets(allocator, page_sheets);
    var all_sheets = std.ArrayListUnmanaged(css.Stylesheet){};
    defer all_sheets.deinit(allocator);
    try all_sheets.append(allocator, ua_sheet);
    for (page_sheets) |s| try all_sheets.append(allocator, s);

    var resolver = css.resolver.StyleResolver.init(allocator);
    const styled_root = try resolver.resolve(document.root, all_sheets.items);
    defer resolver.freeStyledNode(styled_root);

    layout.text_measure.setMeasureFn(&coreMeasure);
    const layout_root = try layout.buildLayoutTree(allocator, styled_root);
    defer {
        layout_root.deinit(allocator);
        allocator.destroy(layout_root);
    }
    const lctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = @floatFromInt(cfg.window.width),
        .viewport_height = @floatFromInt(cfg.window.height),
    };
    layout.layoutTree(layout_root, lctx);

    const dl = try display_list.buildDisplayList(allocator, layout_root);
    my_renderer.setDocument(allocator, layout_root, dl);

    std.debug.print("Metal Browser Engine -- Version 0.1.0-draft\n", .{});
    app.objc.run_application();
}
