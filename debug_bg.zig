const std = @import("std");
const dom = @import("src/dom/mod.zig");
const css = @import("src/css/mod.zig");
const layout = @import("src/layout/mod.zig");

fn walk(sn: *const css.resolver.StyledNode) void {
    if (sn.node.node_type == .element) {
        if (sn.node.getAttribute("class")) |cls| {
            if (std.mem.indexOf(u8, cls, "L3eUgb") != null) {
                const c = sn.style.background_color;
                std.debug.print("L3eUgb bg rgba({d},{d},{d},{d})\n", .{c.r,c.g,c.b,c.a});
            }
        }
    }
    for (sn.children) |child| walk(child);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const html_path = "tests/fidelity/results/google_snapshot.html";
    const file = try std.fs.cwd().openFile(html_path, .{});
    defer file.close();
    const html = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    const document = try dom.parseHTML(allocator, html);

    const ua_sheet = try css.user_agent.getStylesheet(allocator);
    const page_sheets = try css.extractStylesheets(allocator, document.root);
    var all_sheets = std.ArrayListUnmanaged(css.Stylesheet){};
    try all_sheets.append(allocator, ua_sheet);
    for (page_sheets) |s| try all_sheets.append(allocator, s);

    var resolver = css.StyleResolver.init(allocator);
    const styled_root = try resolver.resolve(document.root, all_sheets.items);
    if (styled_root) |sr| walk(sr);
}
