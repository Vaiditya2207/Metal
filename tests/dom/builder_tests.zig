const std = @import("std");
const builder_mod = @import("../../src/dom/builder.zig");
const node_mod = @import("../../src/dom/node.zig");
const tag_mod = @import("../../src/dom/tag.zig");

const parseHTML = builder_mod.parseHTML;
const NodeType = node_mod.NodeType;
const TagName = tag_mod.TagName;

test "parse simple HTML" {
    const doc = try parseHTML(std.testing.allocator, "<html><body><p>Hello</p></body></html>");
    defer doc.deinit();
    try std.testing.expectEqual(NodeType.document, doc.root.node_type);
    try std.testing.expect(doc.root.children.items.len > 0);
}

test "parse implicit structure" {
    const doc = try parseHTML(std.testing.allocator, "<p>Hello</p>");
    defer doc.deinit();
    try std.testing.expect(doc.root.querySelector(.html) != null);
    try std.testing.expect(doc.root.querySelector(.body) != null);
    try std.testing.expect(doc.root.querySelector(.p) != null);
}

test "parse nested elements" {
    const doc = try parseHTML(std.testing.allocator, "<div><span><a href=\"#\">Link</a></span></div>");
    defer doc.deinit();
    const div = doc.root.querySelector(.div);
    try std.testing.expect(div != null);
    try std.testing.expect(div.?.querySelector(.span) != null);
}

test "parse void elements" {
    const doc = try parseHTML(std.testing.allocator, "<p>Before<br>After</p>");
    defer doc.deinit();
    const p = doc.root.querySelector(.p);
    try std.testing.expect(p != null);
    try std.testing.expect(p.?.children.items.len >= 2);
}

test "parse text content extraction" {
    const doc = try parseHTML(std.testing.allocator, "<div><h1>Title</h1><p>Body text</p></div>");
    defer doc.deinit();
    const div = doc.root.querySelector(.div);
    try std.testing.expect(div != null);
    const text = try div.?.getTextContent(doc.arena.allocator());
    try std.testing.expect(text.len > 0);
}

test "parse getElementById" {
    const doc = try parseHTML(std.testing.allocator, "<div id=\"main\"><p>Content</p></div>");
    defer doc.deinit();
    const found = doc.root.getElementById("main");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(TagName.div, found.?.tag);
}

test "parse attributes preserved" {
    const doc = try parseHTML(std.testing.allocator, "<a href=\"http://example.com\" class=\"link\">Click</a>");
    defer doc.deinit();
    const a = doc.root.querySelector(.a);
    try std.testing.expect(a != null);
    try std.testing.expect(a.?.attributes.items.len >= 2);
}

test "parse empty document" {
    const doc = try parseHTML(std.testing.allocator, "");
    defer doc.deinit();
    try std.testing.expectEqual(NodeType.document, doc.root.node_type);
}

test "security: arena cleanup frees all memory" {
    const doc = try parseHTML(std.testing.allocator, "<html><body><div><p>Hello World</p></div></body></html>");
    doc.deinit();
}

test "parse malformed HTML gracefully" {
    const doc = try parseHTML(std.testing.allocator, "<div><p>Unclosed<span>Mismatched</div>");
    defer doc.deinit();
    try std.testing.expect(doc.root.children.items.len > 0);
}

test "parse new void elements" {
    const doc = try parseHTML(std.testing.allocator, "<div><col>Text</div>");
    defer doc.deinit();
    const div = doc.root.querySelector(.div).?;

    // div should have col and Text
    try std.testing.expectEqual(@as(usize, 2), div.children.items.len);
    const col = div.children.items[0];
    const text = div.children.items[1];

    try std.testing.expectEqual(TagName.col, col.tag);
    try std.testing.expectEqual(NodeType.text, text.node_type);

    // col should be empty
    try std.testing.expectEqual(@as(usize, 0), col.children.items.len);
}
