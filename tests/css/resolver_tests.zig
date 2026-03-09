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

test "css_resolve:01 basic style application" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div></div>");
    const stylesheet = try css.Parser.parse(allocator, "div { color: #ff0000; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(css.CssColor.fromRgb(255, 0, 0), div.style.color);
}

test "css_resolve:02 no matching rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div></div>");
    const stylesheet = try css.Parser.parse(allocator, "p { color: #ff0000; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(css.CssColor.fromRgb(0, 0, 0), div.style.color);
}

test "css_resolve:03 specificity ordering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div id=\"foo\" class=\"bar\"></div>");
    const stylesheet = try css.Parser.parse(allocator, ".bar { color: #00ff00; } #foo { color: #ff0000; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(css.CssColor.fromRgb(255, 0, 0), div.style.color);
}

test "css_resolve:04 source order cascade" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div class=\"bar\"></div>");
    const stylesheet = try css.Parser.parse(allocator, ".bar { color: #00ff00; } .bar { color: #0000ff; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(css.CssColor.fromRgb(0, 0, 255), div.style.color);
}

test "css_resolve:05 inheritance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div><p></p></div>");
    const stylesheet = try css.Parser.parse(allocator, "div { color: #ff0000; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const p = findByTag(styled_root, "p").?;
    try testing.expectEqual(css.CssColor.fromRgb(255, 0, 0), p.style.color);
}

test "css_resolve:06 inheritance override" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div><p></p></div>");
    const stylesheet = try css.Parser.parse(allocator, "div { color: #ff0000; } p { color: #00ff00; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const p = findByTag(styled_root, "p").?;
    try testing.expectEqual(css.CssColor.fromRgb(0, 255, 0), p.style.color);
}

test "css_resolve:07 non-inherited property" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div><p></p></div>");
    const stylesheet = try css.Parser.parse(allocator, "div { width: 100px; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const p = findByTag(styled_root, "p").?;
    try testing.expect(p.style.width == null);
}

test "css_resolve:08 inline style override" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div style=\"color: #0000ff;\" class=\"red\"></div>");
    const stylesheet = try css.Parser.parse(allocator, ".red { color: #ff0000; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(css.CssColor.fromRgb(0, 0, 255), div.style.color);
}

test "css_resolve:09 multiple stylesheets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div></div>");
    const s1 = try css.Parser.parse(allocator, "div { color: #ff0000; }");
    const s2 = try css.Parser.parse(allocator, "div { background-color: #00ff00; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{ s1, s2 };
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(css.CssColor.fromRgb(255, 0, 0), div.style.color);
    try testing.expectEqual(css.CssColor.fromRgb(0, 255, 0), div.style.background_color);
}

test "css_resolve:10 tree structure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div><p><span></span></p></div>");
    var resolver = css.StyleResolver.init(allocator);
    const styled_root = (try resolver.resolve(doc.root, &[_]css.Stylesheet{})).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(@as(usize, 1), div.children.len);
    const p = findByTag(styled_root, "p").?;
    try testing.expectEqual(@as(usize, 1), p.children.len);
    const span = findByTag(styled_root, "span").?;
    try testing.expectEqual(@as(usize, 0), span.children.len);
}

test "css_resolve:11 universal selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div><p></p></div>");
    const stylesheet = try css.Parser.parse(allocator, "* { color: #ff0000; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    const p = findByTag(styled_root, "p").?;
    try testing.expectEqual(css.CssColor.fromRgb(255, 0, 0), div.style.color);
    try testing.expectEqual(css.CssColor.fromRgb(255, 0, 0), p.style.color);
}

test "css_resolve:12 descendant matching" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div><p></p></div>");
    const stylesheet = try css.Parser.parse(allocator, "div p { color: #0000ff; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const p = findByTag(styled_root, "p").?;
    try testing.expectEqual(css.CssColor.fromRgb(0, 0, 255), p.style.color);
}

test "css_resolve:13 display: none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div><p></p></div>");
    const stylesheet = try css.Parser.parse(allocator, "div { display: none; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    // div should be missing from the tree
    try testing.expect(findByTag(styled_root, "div") == null);
}

test "css_resolve:14 display: none children" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div><p></p><span></span></div>");
    const stylesheet = try css.Parser.parse(allocator, "p { display: none; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    try testing.expectEqual(@as(usize, 1), styled_root.children.len);
    try testing.expect(findByTag(styled_root, "p") == null);
    try testing.expect(findByTag(styled_root, "span") != null);
}

test "css_resolve:15 background-image url extraction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div></div>");
    const stylesheet = try css.Parser.parse(allocator, "div { background-image: url(\"/img/bg.png\"); }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expect(div.style.background_image_url != null);
    try testing.expectEqualStrings("/img/bg.png", div.style.background_image_url.?);
}

test "css_resolve:16 background shorthand extracts color and url" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div></div>");
    const stylesheet = try css.Parser.parse(allocator, "div { background: #000 url('hero.webp') no-repeat center center; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(css.CssColor.fromRgb(0, 0, 0), div.style.background_color);
    try testing.expect(div.style.background_image_url != null);
    try testing.expectEqualStrings("hero.webp", div.style.background_image_url.?);
}

test "css_resolve:17 flex wrap and gap parsing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div></div>");
    const stylesheet = try css.Parser.parse(allocator, "div { display: flex; flex-wrap: wrap; gap: 12px 8px; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(css.FlexWrap.wrap, div.style.flex_wrap);
    try testing.expectEqual(@as(f32, 12), div.style.row_gap.value);
    try testing.expectEqual(@as(f32, 8), div.style.column_gap.value);
}

test "css_resolve:18 background repeat and size parsing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom.parseHTML(allocator, "<div></div>");
    const stylesheet = try css.Parser.parse(allocator, "div { background: url(bg.png) no-repeat; background-size: cover; }");
    var resolver = css.StyleResolver.init(allocator);
    const stylesheets = [_]css.Stylesheet{stylesheet};
    const styled_root = (try resolver.resolve(doc.root, &stylesheets)).?;

    const div = findByTag(styled_root, "div").?;
    try testing.expectEqual(css.BackgroundRepeat.no_repeat, div.style.background_repeat);
    try testing.expectEqual(css.BackgroundSize.cover, div.style.background_size);
}
