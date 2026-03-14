const std = @import("std");
const dom = @import("dom/mod.zig");
const css = @import("css/mod.zig");
const layout = @import("layout/mod.zig");
const text_measure = @import("layout/text_measure.zig");
const c_text = @cImport({
    @cInclude("text_atlas.h");
});

fn escapeJsonString(allocator: std.mem.Allocator, in: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    for (in) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, c),
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn collectNodesJson(allocator: std.mem.Allocator, box: *const layout.LayoutBox, list: *std.ArrayListUnmanaged([]const u8)) !void {
    const b = box.dimensions.borderBox();

    if (box.styled_node == null) {
        for (box.children.items) |child| {
            try collectNodesJson(allocator, child, list);
        }
        return;
    }

    const sn = box.styled_node.?;

    if (sn.node.node_type == .document) {
        var child_list = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (child_list.items) |s| allocator.free(s);
            child_list.deinit(allocator);
        }
        for (box.children.items) |child| {
            try collectNodesJson(allocator, child, &child_list);
        }

        var out = std.ArrayListUnmanaged(u8){};
        try out.writer(allocator).print("{{\"type\":\"document\",\"children\":[", .{});
        for (child_list.items, 0..) |cs, i| {
            if (i > 0) try out.append(allocator, ',');
            try out.appendSlice(allocator, cs);
        }
        try out.appendSlice(allocator, "]}");
        try list.append(allocator, try out.toOwnedSlice(allocator));
        return;
    }

    if (sn.node.node_type == .text) {
        if (sn.node.data) |d| {
            var trimmed = std.mem.trim(u8, d, " \n\r\t");
            if (trimmed.len == 0) return;
            const preview_len = @min(trimmed.len, 50);
            const preview = trimmed[0..preview_len];

            const escaped = try escapeJsonString(allocator, preview);
            defer allocator.free(escaped);

            var out = std.ArrayListUnmanaged(u8){};
            try out.writer(allocator).print("{{\"type\":\"text\",\"text\":\"{s}{s}\"}}", .{ escaped, if (trimmed.len > 50) "..." else "" });
            try list.append(allocator, try out.toOwnedSlice(allocator));
        }
        return;
    }

    if (sn.node.node_type != .element) return;
    if (sn.node.tag == .script or sn.node.tag == .style) return;

    var has_id = false;
    var has_class = false;
    var id_val: []const u8 = "";
    var class_val: []const u8 = "";

    if (sn.node.getAttribute("id")) |i| {
        has_id = true;
        id_val = i;
    }
    if (sn.node.getAttribute("class")) |c| {
        has_class = true;
        class_val = c;
    }

    const tag_str = sn.node.tag_name_str orelse "unknown";

    var child_list = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (child_list.items) |s| allocator.free(s);
        child_list.deinit(allocator);
    }
    for (box.children.items) |child| {
        try collectNodesJson(allocator, child, &child_list);
    }

    var out = std.ArrayListUnmanaged(u8){};
    var writer = out.writer(allocator);

    try writer.print("{{\"type\":\"element\",\"tag\":\"{s}\"", .{tag_str});
    if (has_id) try writer.print(",\"id\":\"{s}\"", .{try escapeJsonString(allocator, id_val)});
    if (has_class) try writer.print(",\"className\":\"{s}\"", .{try escapeJsonString(allocator, class_val)});

    try writer.print(",\"rect\":{{\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d}}}", .{
        @as(i32, @intFromFloat(@round(b.x))),
        @as(i32, @intFromFloat(@round(b.y))),
        @as(i32, @intFromFloat(@round(b.width))),
        @as(i32, @intFromFloat(@round(b.height))),
    });

    try writer.print(",\"style\":{{", .{});

    const display_str = @tagName(sn.style.display);
    try writer.print("\"display\":\"{s}\"", .{display_str});
    // Font size
    try writer.print(",\"fontSize\":\"{d:.0}px\"", .{sn.style.font_size.value});
    // Font weight
    try writer.print(",\"fontWeight\":\"{d:.0}\"", .{sn.style.font_weight});
    // Font style
    const font_style_str = @tagName(sn.style.font_style);
    try writer.print(",\"fontStyle\":\"{s}\"", .{font_style_str});
    // Visibility
    const vis_str = @tagName(sn.style.visibility);
    try writer.print(",\"visibility\":\"{s}\"", .{vis_str});
    // Color (as rgb string)
    try writer.print(",\"color\":\"rgb({d}, {d}, {d})\"", .{ sn.style.color.r, sn.style.color.g, sn.style.color.b });
    // Background color
    try writer.print(",\"backgroundColor\":\"rgb({d}, {d}, {d})\"", .{ sn.style.background_color.r, sn.style.background_color.g, sn.style.background_color.b });
    try writer.print("}}", .{});

    try writer.print(",\"children\":[", .{});
    for (child_list.items, 0..) |cs, i| {
        if (i > 0) try out.append(allocator, ',');
        try out.appendSlice(allocator, cs);
    }
    try writer.print("]}}", .{});

    try list.append(allocator, try out.toOwnedSlice(allocator));
}

pub fn main() !void {
    text_measure.setMeasureFn(coreTextMeasure);
    text_measure.setLineHeightFn(coreTextLineHeight);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = std.process.args();
    _ = args.skip();

    const file_path = args.next() orelse {
        std.debug.print("Usage: dump_dom <html_file>\n", .{});
        return;
    };

    const out_path = args.next() orelse {
        std.debug.print("Usage: dump_dom <html_file> <output_json>\n", .{});
        return;
    };

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const max_size = 10 * 1024 * 1024;
    const html = try file.readToEndAlloc(allocator, max_size);

    const document = try dom.parseHTML(allocator, html);

    // Use the REAL pipeline: UA stylesheet + page <style> tags + inline styles
    // (same wiring as src/main.zig and src/render/renderer.zig)
    const ua_sheet = try css.user_agent.getStylesheet(allocator);
    const page_sheets = try css.extractStylesheets(allocator, document.root);

    var all_sheets = std.ArrayListUnmanaged(css.Stylesheet){};
    try all_sheets.append(allocator, ua_sheet);
    for (page_sheets) |s| try all_sheets.append(allocator, s);

    std.debug.print("[dump_dom] HTML: {d} bytes | Stylesheets: 1 UA + {d} page = {d} total\n", .{ html.len, page_sheets.len, all_sheets.items.len });

    // Count UA rules
    var total_rules: usize = 0;
    for (all_sheets.items) |sheet| total_rules += sheet.rules.len;
    std.debug.print("[dump_dom] Total CSS rules: {d}\n", .{total_rules});

    var resolver = css.StyleResolver.init(allocator);
    const styled_root = try resolver.resolve(document.root, all_sheets.items);

    if (styled_root) |sr| {
        const layout_root = try layout.buildLayoutTree(allocator, sr);
        // Simulate a 1200x800 viewport exactly as Chrome did
        const lctx = layout.LayoutContext{
            .allocator = allocator,
            .viewport_width = 1200.0,
            .viewport_height = 800.0,
        };
        layout.layoutTree(layout_root, lctx);

        // Count layout nodes for diagnostics
        var node_count: usize = 0;
        var zero_size_count: usize = 0;
        countNodes(layout_root, &node_count, &zero_size_count);
        std.debug.print("[dump_dom] Layout nodes: {d} | Zero-size: {d}\n", .{ node_count, zero_size_count });

        var json_out = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (json_out.items) |s| allocator.free(s);
            json_out.deinit(allocator);
        }

        try collectNodesJson(allocator, layout_root, &json_out);

        var out_file = try std.fs.cwd().createFile(out_path, .{});
        defer out_file.close();

        if (json_out.items.len > 0) {
            try out_file.writeAll(json_out.items[0]);
            std.debug.print("[dump_dom] JSON output: {d} bytes\n", .{json_out.items[0].len});
        } else {
            try out_file.writeAll("{}");
            std.debug.print("[dump_dom] WARNING: empty JSON output\n", .{});
        }
    } else {
        std.debug.print("[dump_dom] ERROR: Could not style root.\n", .{});
    }
}

fn countNodes(box: *const layout.LayoutBox, count: *usize, zero_count: *usize) void {
    count.* += 1;
    const b = box.dimensions.borderBox();
    if (b.width == 0 and b.height == 0) zero_count.* += 1;
    for (box.children.items) |child| countNodes(child, count, zero_count);
}

fn coreTextMeasure(text: []const u8, font_size: f32, _: f32) f32 {
    if (text.len == 0) return 0;
    return c_text.measure_text_width(text.ptr, @intCast(text.len), font_size);
}

fn coreTextLineHeight(font_family: []const u8, font_size: f32, font_weight: f32) f32 {
    var buf: [256]u8 = undefined;
    const len = @min(font_family.len, 255);
    @memcpy(buf[0..len], font_family[0..len]);
    buf[len] = 0;
    return c_text.get_font_line_height_ratio(&buf, font_size, font_weight);
}
