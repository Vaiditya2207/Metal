const std = @import("std");
const dom = @import("dom/mod.zig");
const css = @import("css/mod.zig");
const layout = @import("layout/mod.zig");

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
            try out.writer(allocator).print("{{\"type\":\"text\",\"text\":\"{s}{s}\"}}", .{escaped, if (trimmed.len > 50) "..." else ""});
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

    // Default UA stylesheet for testing
    const ua_css = "html, body, div, p { display: block; }";
    var resolver = css.StyleResolver.init(allocator);
    const ua_sheet = try css.Parser.parse(allocator, ua_css);
    const stylesheets = [_]css.Stylesheet{ua_sheet};

    const styled_root = try resolver.resolve(document.root, &stylesheets);

    if (styled_root) |sr| {
        const layout_root = try layout.buildLayoutTree(allocator, sr);
        // Simulate a 1200x800 viewport exactly as Chrome did
        const lctx = layout.LayoutContext{
            .allocator = allocator,
            .viewport_width = 1200.0,
            .viewport_height = 800.0,
        };
        layout.layoutTree(layout_root, lctx);
        
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
        } else {
            try out_file.writeAll("{}");
        }
    } else {
        std.debug.print("Could not style root.\n", .{});
    }
}
