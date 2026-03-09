const std = @import("std");
const testing = std.testing;
const dom = @import("../../src/dom/mod.zig");
const css = @import("../../src/css/mod.zig");

fn findByTag(sn: *const css.StyledNode, tag: []const u8) ?*const css.StyledNode {
    if (sn.node.node_type == .element) {
        if (sn.node.tag_name_str) |t| {
            if (std.mem.eql(u8, t, tag)) return sn;
        }
    }
    for (sn.children) |child| {
        if (findByTag(child, tag)) |found| return found;
    }
    return null;
}

test "ua_stylesheet:01 parses successfully" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ua_sheet = try css.user_agent.getStylesheet(allocator);
    try testing.expect(ua_sheet.rules.len > 0);
}

test "ua_stylesheet:02 applies block display to p" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<p>hello</p>");
    const ua_sheet = try css.user_agent.getStylesheet(allocator);
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{ua_sheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const p = findByTag(styled_root, "p").?;
    try testing.expectEqual(css.Display.block, p.style.display);
}

test "ua_stylesheet:03 applies h1 font size and weight" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<h1>heading</h1>");
    const ua_sheet = try css.user_agent.getStylesheet(allocator);
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{ua_sheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const h1 = findByTag(styled_root, "h1").?;
    try testing.expectEqual(@as(f32, 32), h1.style.font_size.value);
    try testing.expectEqual(@as(f32, 700), h1.style.font_weight);
}

test "ua_stylesheet:04 author styles override ua stylesheet" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<p>hello</p>");
    const ua_sheet = try css.user_agent.getStylesheet(allocator);
    const author_sheet = try css.Parser.parse(allocator, "p { margin-top: 0px }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{ ua_sheet, author_sheet };
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const p = findByTag(styled_root, "p").?;
    try testing.expectEqual(@as(f32, 0), p.style.margin_top.value);
}
