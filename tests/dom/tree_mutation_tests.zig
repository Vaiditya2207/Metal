const std = @import("std");
const document_mod = @import("../../src/dom/document.zig");
const node_mod = @import("../../src/dom/node.zig");

const Document = document_mod.Document;
const Node = node_mod.Node;

test "insertBefore inserts at correct position" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const parent = try doc.createElement("div");
    const a = try doc.createElement("span");
    const b = try doc.createElement("span");
    const c = try doc.createElement("span");

    try parent.appendChild(a, doc.limits);
    try parent.appendChild(b, doc.limits);
    try parent.insertBefore(c, b, doc.limits);

    try std.testing.expectEqual(@as(usize, 3), parent.children.items.len);
    try std.testing.expect(parent.children.items[0] == a);
    try std.testing.expect(parent.children.items[1] == c);
    try std.testing.expect(parent.children.items[2] == b);
    try std.testing.expect(c.parent == parent);
    try std.testing.expectEqual(@as(u16, 1), c.depth);
}

test "insertBefore appends when ref is null" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const parent = try doc.createElement("div");
    const a = try doc.createElement("span");
    const b = try doc.createElement("span");

    try parent.appendChild(a, doc.limits);
    try parent.insertBefore(b, null, doc.limits);

    try std.testing.expectEqual(@as(usize, 2), parent.children.items.len);
    try std.testing.expect(parent.children.items[0] == a);
    try std.testing.expect(parent.children.items[1] == b);
    try std.testing.expect(b.parent == parent);
}

test "insertBefore moves from old parent" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const parent1 = try doc.createElement("div");
    const parent2 = try doc.createElement("div");
    const c = try doc.createElement("span");

    try doc.root.appendChild(parent1, doc.limits);
    try doc.root.appendChild(parent2, doc.limits);
    try parent1.appendChild(c, doc.limits);

    try std.testing.expectEqual(@as(usize, 1), parent1.children.items.len);

    try parent2.insertBefore(c, null, doc.limits);

    try std.testing.expectEqual(@as(usize, 0), parent1.children.items.len);
    try std.testing.expectEqual(@as(usize, 1), parent2.children.items.len);
    try std.testing.expect(parent2.children.items[0] == c);
    try std.testing.expect(c.parent == parent2);
}

test "replaceChild swaps correctly" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const parent = try doc.createElement("div");
    const a = try doc.createElement("span");
    const b = try doc.createElement("span");
    const c = try doc.createElement("span");
    const d = try doc.createElement("span");

    try parent.appendChild(a, doc.limits);
    try parent.appendChild(b, doc.limits);
    try parent.appendChild(c, doc.limits);

    const old = parent.replaceChild(d, b);

    try std.testing.expect(old != null);
    try std.testing.expect(old.? == b);
    try std.testing.expect(b.parent == null);

    try std.testing.expectEqual(@as(usize, 3), parent.children.items.len);
    try std.testing.expect(parent.children.items[0] == a);
    try std.testing.expect(parent.children.items[1] == d);
    try std.testing.expect(parent.children.items[2] == c);
    try std.testing.expect(d.parent == parent);
    try std.testing.expectEqual(@as(u16, 1), d.depth);
}

test "replaceChild returns null if old not found" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const parent = try doc.createElement("div");
    const a = try doc.createElement("span");
    const b = try doc.createElement("span");
    const c = try doc.createElement("span");

    try parent.appendChild(a, doc.limits);

    const result = parent.replaceChild(b, c);

    try std.testing.expect(result == null);
    try std.testing.expectEqual(@as(usize, 1), parent.children.items.len);
    try std.testing.expect(parent.children.items[0] == a);
}
