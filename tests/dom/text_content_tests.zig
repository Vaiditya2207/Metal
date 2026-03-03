const std = @import("std");
const document_mod = @import("../../src/dom/document.zig");
const node_mod = @import("../../src/dom/node.zig");

const Document = document_mod.Document;
const Node = node_mod.Node;

test "setTextContent replaces children with text node" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const parent = try doc.createElement("div");
    const a = try doc.createElement("span");
    const b = try doc.createElement("span");
    try parent.appendChild(a, doc.limits);
    try parent.appendChild(b, doc.limits);

    try std.testing.expectEqual(@as(usize, 2), parent.children.items.len);

    try parent.setTextContent("hello", doc.limits);

    try std.testing.expectEqual(@as(usize, 1), parent.children.items.len);
    const child = parent.children.items[0];
    try std.testing.expectEqual(node_mod.NodeType.text, child.node_type);
    try std.testing.expectEqualStrings("hello", child.data.?);
}

test "setTextContent with empty string removes all children" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const parent = try doc.createElement("div");
    const a = try doc.createElement("span");
    try parent.appendChild(a, doc.limits);

    try std.testing.expectEqual(@as(usize, 1), parent.children.items.len);

    try parent.setTextContent("", doc.limits);

    try std.testing.expectEqual(@as(usize, 0), parent.children.items.len);
}

test "setTextContent on element with no children" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const parent = try doc.createElement("div");
    try std.testing.expectEqual(@as(usize, 0), parent.children.items.len);

    try parent.setTextContent("world", doc.limits);

    try std.testing.expectEqual(@as(usize, 1), parent.children.items.len);
    const child = parent.children.items[0];
    try std.testing.expectEqual(node_mod.NodeType.text, child.node_type);
    try std.testing.expectEqualStrings("world", child.data.?);
}

test "setTextContent overwrites previous text content" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const parent = try doc.createElement("div");
    try parent.setTextContent("first", doc.limits);
    try std.testing.expectEqual(@as(usize, 1), parent.children.items.len);
    try std.testing.expectEqualStrings("first", parent.children.items[0].data.?);

    try parent.setTextContent("second", doc.limits);
    try std.testing.expectEqual(@as(usize, 1), parent.children.items.len);
    try std.testing.expectEqualStrings("second", parent.children.items[0].data.?);

    const text = try parent.getTextContent(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("second", text);
}
