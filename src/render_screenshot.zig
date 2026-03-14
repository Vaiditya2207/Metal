const std = @import("std");
const dom = @import("dom/mod.zig");
const css = @import("css/mod.zig");
const layout = @import("layout/mod.zig");
const text_measure = @import("layout/text_measure.zig");
const display_list_mod = @import("render/display_list.zig");
const compositor_mod = @import("render/compositor.zig");
const text_mod = @import("render/text.zig");

const c = @cImport({
    @cInclude("objc_bridge.h");
    @cInclude("screenshot_bridge.h");
    @cInclude("text_atlas.h");
});

extern "C" fn MTLCreateSystemDefaultDevice() ?*anyopaque;

fn coreTextMeasure(text: []const u8, font_size: f32, _: f32) f32 {
    if (text.len == 0) return 0;
    return c.measure_text_width(text.ptr, @intCast(text.len), font_size);
}

fn coreTextLineHeight(font_family: []const u8, font_size: f32, font_weight: f32) f32 {
    var buf: [256]u8 = undefined;
    const len = @min(font_family.len, 255);
    @memcpy(buf[0..len], font_family[0..len]);
    buf[len] = 0;
    return c.get_font_line_height_ratio(&buf, font_size, font_weight);
}

fn parseFloatArg(s: []const u8) f32 {
    return std.fmt.parseFloat(f32, s) catch 1200.0;
}

fn usage() void {
    std.debug.print("Usage: render_screenshot <html_file> <output.png> [width] [height]\n", .{});
    std.debug.print("  width   - viewport width  (default 1200)\n", .{});
    std.debug.print("  height  - viewport height  (default 800)\n", .{});
}

pub fn main() !void {
    // Set text measurement to use CoreText
    text_measure.setMeasureFn(coreTextMeasure);
    text_measure.setLineHeightFn(coreTextLineHeight);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parse args
    var args = std.process.args();
    _ = args.skip(); // program name
    const html_path = args.next() orelse {
        usage();
        return;
    };
    const png_path = args.next() orelse {
        usage();
        return;
    };
    const viewport_w: f32 = if (args.next()) |w| parseFloatArg(w) else 1200.0;
    const viewport_h: f32 = if (args.next()) |h_arg| parseFloatArg(h_arg) else 800.0;

    // Read HTML file
    const file = try std.fs.cwd().openFile(html_path, .{});
    defer file.close();
    const html = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);

    std.debug.print("[screenshot] HTML: {d} bytes, viewport: {d}x{d}\n", .{ html.len, @as(u32, @intFromFloat(viewport_w)), @as(u32, @intFromFloat(viewport_h)) });

    // Parse HTML -> DOM
    const document = try dom.parseHTML(allocator, html);

    // Resolve styles
    const ua_sheet = try css.user_agent.getStylesheet(allocator);
    const page_sheets = try css.extractStylesheets(allocator, document.root);

    var all_sheets = std.ArrayListUnmanaged(css.Stylesheet){};
    try all_sheets.append(allocator, ua_sheet);
    for (page_sheets) |s| try all_sheets.append(allocator, s);

    var resolver = css.StyleResolver.init(allocator);
    const styled_root = try resolver.resolve(document.root, all_sheets.items);

    if (styled_root == null) {
        std.debug.print("ERROR: Could not resolve styles\n", .{});
        return;
    }

    // Build layout tree
    const layout_root = try layout.buildLayoutTree(allocator, styled_root.?);
    const lctx = layout.LayoutContext{
        .allocator = allocator,
        .viewport_width = viewport_w,
        .viewport_height = viewport_h,
    };
    layout.layoutTree(layout_root, lctx);

    // Build display list
    var dl = try display_list_mod.buildDisplayList(allocator, layout_root, null);
    defer dl.deinit();

    std.debug.print("[screenshot] Display list: {d} commands\n", .{dl.commands.items.len});

    for (dl.commands.items, 0..) |cmd, i| {
        switch (cmd) {
            .draw_rect => |r| std.debug.print("  [{d}] draw_rect: x={d} y={d} w={d} h={d} color=rgb({d},{d},{d},{d})\n", .{ i, r.rect.x, r.rect.y, r.rect.width, r.rect.height, r.color.r, r.color.g, r.color.b, r.color.a }),
            .draw_text => |t| std.debug.print("  [{d}] draw_text: '{s}' at x={d} y={d} color=rgb({d},{d},{d},{d})\n", .{ i, t.text, t.rect.x, t.rect.y, t.color.r, t.color.g, t.color.b, t.color.a }),
            .draw_image => |im| std.debug.print("  [{d}] draw_image: x={d} y={d} w={d} h={d}\n", .{ i, im.rect.x, im.rect.y, im.rect.width, im.rect.height }),
            .draw_svg => |s| std.debug.print("  [{d}] draw_svg: x={d} y={d} w={d} h={d}\n", .{ i, s.rect.x, s.rect.y, s.rect.width, s.rect.height }),
            else => std.debug.print("  [{d}] {s}\n", .{ i, @tagName(cmd) }),
        }
    }

    // --- GPU SETUP ---
    const device = MTLCreateSystemDefaultDevice() orelse {
        std.debug.print("ERROR: No Metal device available\n", .{});
        return;
    };

    const queue: *anyopaque = c.create_command_queue(device) orelse {
        std.debug.print("ERROR: Could not create command queue\n", .{});
        return;
    };

    // Create pipelines
    const rect_pipeline: *anyopaque = c.create_render_pipeline(device) orelse {
        std.debug.print("ERROR: Could not create rect pipeline\n", .{});
        return;
    };
    const image_pipeline: ?*anyopaque = c.create_image_pipeline(device);

    // Create text renderer
    const scale: f32 = 2.0; // Retina
    const text_renderer = text_mod.TextRenderer.init(device, queue, 64.0, scale) catch {
        std.debug.print("ERROR: Could not create text renderer\n", .{});
        return;
    };

    // Create offscreen texture (at 2x for Retina)
    const tex_w: c_int = @intFromFloat(viewport_w * scale);
    const tex_h: c_int = @intFromFloat(viewport_h * scale);
    const texture: *anyopaque = c.create_offscreen_texture(device, tex_w, tex_h) orelse {
        std.debug.print("ERROR: Could not create offscreen texture\n", .{});
        return;
    };

    // Begin offscreen frame
    const fc: *anyopaque = c.begin_offscreen_frame(device, queue, texture) orelse {
        std.debug.print("ERROR: Could not begin offscreen frame\n", .{});
        return;
    };

    // Build compositor
    var svg_cache: std.StringArrayHashMapUnmanaged(*anyopaque) = .{};
    const comp = compositor_mod.Compositor{
        .rect_pipeline = rect_pipeline,
        .text_renderer = &text_renderer,
        .image_pipeline = image_pipeline,
        .device = device,
        .command_queue = queue,
        .allocator = allocator,
        .svg_cache = &svg_cache,
    };

    // Render via the offscreen path (no toolbar offset, no view)
    comp.renderOffscreen(fc, viewport_w, viewport_h, scale, &dl, 0.0);

    // End frame and save
    c.end_offscreen_frame(fc);

    // Null-terminate the path for C interop
    const png_path_z = try allocator.dupeZ(u8, png_path);
    const result = c.save_texture_to_png(texture, png_path_z.ptr);
    if (result == 0) {
        std.debug.print("[screenshot] Saved {d}x{d} PNG to {s}\n", .{ tex_w, tex_h, png_path });
    } else {
        std.debug.print("ERROR: Failed to save PNG to {s}\n", .{png_path});
    }
}
