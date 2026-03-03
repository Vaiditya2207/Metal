const std = @import("std");
const document_mod = @import("../../src/dom/document.zig");
const node_mod = @import("../../src/dom/node.zig");
const tag_mod = @import("../../src/dom/tag.zig");

const Document = document_mod.Document;
const Node = node_mod.Node;
const NodeType = node_mod.NodeType;
const TagName = tag_mod.TagName;

test "create document" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    try std.testing.expectEqual(NodeType.document, doc.root.node_type);
}

test "create element" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const div = try doc.createElement("div");
    try std.testing.expectEqual(TagName.div, div.tag);
}

test "appendChild and relationships" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const body = try doc.createElement("body");
    try doc.root.appendChild(body, doc.limits);
    try std.testing.expectEqual(@as(usize, 1), doc.root.children.items.len);
    try std.testing.expect(body.parent == doc.root);
    try std.testing.expectEqual(@as(u16, 1), body.depth);
}

test "removeChild" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const body = try doc.createElement("body");
    try doc.root.appendChild(body, doc.limits);
    doc.root.removeChild(body);
    try std.testing.expectEqual(@as(usize, 0), doc.root.children.items.len);
}

test "getElementById" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const div = try doc.createElement("div");
    try div.attributes.append(doc.arena.allocator(), .{ .name = "id", .value = "main" });
    try doc.root.appendChild(div, doc.limits);
    const found = doc.root.getElementById("main");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(TagName.div, found.?.tag);
}

test "querySelector by tag" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const body = try doc.createElement("body");
    try doc.root.appendChild(body, doc.limits);
    const p = try doc.createElement("p");
    try body.appendChild(p, doc.limits);
    const found = doc.root.querySelector(.p);
    try std.testing.expect(found != null);
}

test "getTextContent" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    const p = try doc.createElement("p");
    try doc.root.appendChild(p, doc.limits);
    const text = try doc.createTextNode("Hello World");
    try p.appendChild(text, doc.limits);
    const content = try p.getTextContent(doc.arena.allocator());
    try std.testing.expectEqualStrings("Hello World", content);
}

test "node count tracking" {
    const doc = try Document.init(std.heap.page_allocator);
    defer doc.deinit();
    try std.testing.expect(doc.node_count == 1);
    _ = try doc.createElement("div");
    try std.testing.expect(doc.node_count == 2);
}
