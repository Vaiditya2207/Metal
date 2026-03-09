const std = @import("std");
const selector_mod = @import("../../src/css/selector.zig");
const dom_node = @import("../../src/dom/node.zig");
const dom_builder = @import("../../src/dom/builder.zig");

test "css_sel:01 parse simple tag selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sel = try selector_mod.Selector.parse(allocator, "div");
    try std.testing.expectEqual(@as(usize, 1), sel.components.len);
    try std.testing.expectEqualStrings("div", sel.components[0].part.tag.?);
    try std.testing.expectEqual(@as(u16, 1), sel.specificity.c);
}

test "css_sel:02 parse class selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sel = try selector_mod.Selector.parse(allocator, ".main");
    try std.testing.expectEqual(@as(usize, 1), sel.components.len);
    try std.testing.expectEqual(@as(usize, 1), sel.components[0].part.classes.len);
    try std.testing.expectEqualStrings("main", sel.components[0].part.classes[0]);
    try std.testing.expectEqual(@as(u16, 1), sel.specificity.b);
}

test "css_sel:03 parse id selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sel = try selector_mod.Selector.parse(allocator, "#header");
    try std.testing.expectEqual(@as(usize, 1), sel.components.len);
    try std.testing.expectEqualStrings("header", sel.components[0].part.id.?);
    try std.testing.expectEqual(@as(u16, 1), sel.specificity.a);
}

test "css_sel:04 parse universal selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sel = try selector_mod.Selector.parse(allocator, "*");
    try std.testing.expectEqual(@as(usize, 1), sel.components.len);
    try std.testing.expect(sel.components[0].part.universal);
    try std.testing.expectEqual(@as(u16, 0), sel.specificity.a);
    try std.testing.expectEqual(@as(u16, 0), sel.specificity.b);
    try std.testing.expectEqual(@as(u16, 0), sel.specificity.c);
}

test "css_sel:05 parse compound selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sel = try selector_mod.Selector.parse(allocator, "div.main#content");
    try std.testing.expectEqual(@as(usize, 1), sel.components.len);
    try std.testing.expectEqualStrings("div", sel.components[0].part.tag.?);
    try std.testing.expectEqualStrings("main", sel.components[0].part.classes[0]);
    try std.testing.expectEqualStrings("content", sel.components[0].part.id.?);
    try std.testing.expectEqual(@as(u16, 1), sel.specificity.a);
    try std.testing.expectEqual(@as(u16, 1), sel.specificity.b);
    try std.testing.expectEqual(@as(u16, 1), sel.specificity.c);
}

test "css_sel:06 parse descendant selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sel = try selector_mod.Selector.parse(allocator, "div p");
    try std.testing.expectEqual(@as(usize, 2), sel.components.len);
    try std.testing.expectEqual(selector_mod.Combinator.descendant, sel.components[1].combinator);
    try std.testing.expectEqualStrings("div", sel.components[0].part.tag.?);
    try std.testing.expectEqualStrings("p", sel.components[1].part.tag.?);
}

test "css_sel:07 parse child selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sel = try selector_mod.Selector.parse(allocator, "div > p");
    try std.testing.expectEqual(@as(usize, 2), sel.components.len);
    try std.testing.expectEqual(selector_mod.Combinator.child, sel.components[1].combinator);
}

test "css_sel:08 specificity calculation" {
    const s1 = selector_mod.Specificity{ .a = 1, .b = 0, .c = 0 };
    const s2 = selector_mod.Specificity{ .a = 0, .b = 10, .c = 0 };
    try std.testing.expect(s1.greaterThan(s2));

    const s3 = selector_mod.Specificity{ .a = 0, .b = 1, .c = 5 };
    const s4 = selector_mod.Specificity{ .a = 0, .b = 1, .c = 2 };
    try std.testing.expect(s3.greaterThan(s4));
}

test "css_sel:09 match tag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div id=\"t1\"></div></body></html>");
    const div = doc.root.getElementById("t1").?;

    const sel = try selector_mod.Selector.parse(allocator, "div");
    try std.testing.expect(sel.matchesNode(div));

    const sel2 = try selector_mod.Selector.parse(allocator, "p");
    try std.testing.expect(!sel2.matchesNode(div));
}

test "css_sel:10 match class" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div id=\"t2\" class=\"foo bar\"></div></body></html>");
    const div = doc.root.getElementById("t2").?;

    const sel = try selector_mod.Selector.parse(allocator, ".foo");
    try std.testing.expect(sel.matchesNode(div));

    const sel2 = try selector_mod.Selector.parse(allocator, ".bar");
    try std.testing.expect(sel2.matchesNode(div));

    const sel3 = try selector_mod.Selector.parse(allocator, ".baz");
    try std.testing.expect(!sel3.matchesNode(div));
}

test "css_sel:11 match id" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div id=\"main\"></div></body></html>");
    const div = doc.root.getElementById("main").?;

    const sel = try selector_mod.Selector.parse(allocator, "#main");
    try std.testing.expect(sel.matchesNode(div));

    const sel2 = try selector_mod.Selector.parse(allocator, "#other");
    try std.testing.expect(!sel2.matchesNode(div));
}

test "css_sel:12 match descendant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div><p><span id=\"target\"></span></p></div></body></html>");
    const span = doc.root.getElementById("target").?;

    const sel = try selector_mod.Selector.parse(allocator, "div span");
    try std.testing.expect(sel.matchesNode(span));

    const sel2 = try selector_mod.Selector.parse(allocator, "p span");
    try std.testing.expect(sel2.matchesNode(span));

    const sel3 = try selector_mod.Selector.parse(allocator, "div p span");
    try std.testing.expect(sel3.matchesNode(span));

    const sel4 = try selector_mod.Selector.parse(allocator, "section span");
    try std.testing.expect(!sel4.matchesNode(span));
}

test "css_sel:13 match child" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div><p><span id=\"target\"></span></p></div></body></html>");
    const span = doc.root.getElementById("target").?;

    const sel = try selector_mod.Selector.parse(allocator, "p > span");
    try std.testing.expect(sel.matchesNode(span));

    const sel2 = try selector_mod.Selector.parse(allocator, "div > span");
    try std.testing.expect(!sel2.matchesNode(span));
}

test "css_sel:14 max selector parts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Default max_selector_parts is 32. Let's try 32 parts.
    const sel_str = "div " ** 31 ++ "p";
    const sel = try selector_mod.Selector.parse(allocator, sel_str);
    try std.testing.expectEqual(@as(usize, 32), sel.components.len);
}

test "css_sel:15 universal with class does not match without class" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div></div></body></html>");
    const body = doc.root.children.items[0];
    const div = body.children.items[0];

    const sel = try selector_mod.Selector.parse(allocator, "*.foo");
    try std.testing.expect(!sel.matchesNode(div));
}

test "css_sel:16 universal with class matches with class" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div class=\"foo\"></div></body></html>");

    const div = findDiv(doc.root);
    try std.testing.expect(div != null);
    const sel = try selector_mod.Selector.parse(allocator, "*.foo");
    try std.testing.expect(sel.matchesNode(div.?));
}

test "css_sel:17 attribute selector exists and equals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><input id=\"t\" type=\"search\" disabled></input></body></html>");
    const input = doc.root.getElementById("t").?;

    const has_attr = try selector_mod.Selector.parse(allocator, "input[disabled]");
    try std.testing.expect(has_attr.matchesNode(input));

    const eq_attr = try selector_mod.Selector.parse(allocator, "input[type=search]");
    try std.testing.expect(eq_attr.matchesNode(input));

    const not_eq = try selector_mod.Selector.parse(allocator, "input[type=text]");
    try std.testing.expect(!not_eq.matchesNode(input));
}

test "css_sel:18 root pseudo matches html root element" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div id=\"x\"></div></body></html>");
    const html = doc.root.children.items[0];
    const div = doc.root.getElementById("x").?;

    const sel = try selector_mod.Selector.parse(allocator, ":root");
    try std.testing.expect(sel.matchesNode(html));
    try std.testing.expect(!sel.matchesNode(div));
}

test "css_sel:19 not pseudo simple selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div id=\"a\" class=\"foo\"></div><div id=\"b\"></div></body></html>");
    const a = doc.root.getElementById("a").?;
    const b = doc.root.getElementById("b").?;

    const sel = try selector_mod.Selector.parse(allocator, "div:not(.foo)");
    try std.testing.expect(!sel.matchesNode(a));
    try std.testing.expect(sel.matchesNode(b));
}

test "css_sel:20 is where pseudo simple selector list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const doc = try dom_builder.parseHTML(allocator, "<html><body><div id=\"a\" class=\"x\"></div><p id=\"b\"></p></body></html>");
    const a = doc.root.getElementById("a").?;
    const b = doc.root.getElementById("b").?;

    const sel_is = try selector_mod.Selector.parse(allocator, ":is(div,p)");
    try std.testing.expect(sel_is.matchesNode(a));
    try std.testing.expect(sel_is.matchesNode(b));

    const sel_where = try selector_mod.Selector.parse(allocator, "div:where(.x,.y)");
    try std.testing.expect(sel_where.matchesNode(a));
}

fn findDiv(node: *dom_node.Node) ?*dom_node.Node {
    if (node.node_type == .element and node.tag_name_str != null and std.mem.eql(u8, node.tag_name_str.?, "div")) return node;
    for (node.children.items) |child| {
        if (findDiv(child)) |found| return found;
    }
    return null;
}
