const std = @import("std");
const dom = @import("dom/mod.zig");
const css = @import("css/mod.zig");
const layout = @import("layout/mod.zig");

fn printLayoutTree(box: *const layout.LayoutBox, depth: usize) void {
    var i: usize = 0;
    while (i < depth) : (i += 1) std.debug.print("  ", .{});

    const b = box.dimensions.borderBox();

    var tag_name: []const u8 = "anonymous";
    var text_preview: []const u8 = "";
    if (box.styled_node) |sn| {
        if (sn.node.tag_name_str) |t| {
            tag_name = t;
        } else if (sn.node.node_type == .text) {
            tag_name = "text";
            if (sn.node.data) |d| {
                const len = @min(d.len, 20);
                text_preview = d[0..len];
            }
        }
    }

    std.debug.print("<{s}> [{s}] x={d:.1} y={d:.1} w={d:.1} h={d:.1}", .{ tag_name, @tagName(box.box_type), b.x, b.y, b.width, b.height });
    if (text_preview.len > 0) {
        var clean: [20]u8 = undefined;
        for (text_preview, 0..) |c, j| {
            clean[j] = if (c == '\n') ' ' else c;
        }
        std.debug.print(" \"{s}...\"", .{clean[0..text_preview.len]});
    }
    std.debug.print("\n", .{});

    for (box.children.items) |child| {
        printLayoutTree(child, depth + 1);
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const html =
        \\<div style="width: 400px; padding: 10px; margin: 20px;">
        \\  <div style="display: flex; flex-direction: row; justify-content: space-between;">
        \\    <div style="width: 100px; height: 50px; background-color: red;"></div>
        \\    <div style="width: 100px; height: 50px; background-color: blue;"></div>
        \\  </div>
        \\  <p>Hello world! This is a simple test.</p>
        \\</div>
    ;

    std.debug.print("--- Input HTML ---\n{s}\n\n", .{html});

    // 1. Parse DOM
    const doc = try dom.parseHTML(allocator, html);

    // 2. Resolve Styles
    const ua_css = "html, body, div, p { display: block; }";
    var resolver = css.StyleResolver.init(allocator);
    const ua_sheet = try css.Parser.parse(allocator, ua_css);
    const stylesheets = [_]css.Stylesheet{ua_sheet};

    const styled_root = try resolver.resolve(doc.root, &stylesheets);

    // 3. Build Layout Tree
    const layout_root = try layout.buildLayoutTree(allocator, styled_root);

    // 4. Run Layout (Viewport: 800px)
    layout.layoutTree(layout_root, .{ .allocator = allocator, .viewport_width = 800.0, .viewport_height = 600.0 });

    std.debug.print("--- Metal Engine Layout Tree ---\n", .{});
    printLayoutTree(layout_root, 0);
}
