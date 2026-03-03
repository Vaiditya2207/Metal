const std = @import("std");
const document_mod = @import("../../src/dom/document.zig");

const Document = document_mod.Document;

test "setAttribute adds new attribute" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const el = try doc.createElement("div");
    try el.setAttribute("class", "foo");

    const val = el.getAttribute("class");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("foo", val.?);
}

test "setAttribute updates existing attribute" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const el = try doc.createElement("div");
    try el.setAttribute("class", "foo");
    try el.setAttribute("class", "bar");

    const val = el.getAttribute("class");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("bar", val.?);
    try std.testing.expectEqual(@as(usize, 1), el.attributes.items.len);
}

test "removeAttribute removes existing" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const el = try doc.createElement("div");
    try el.setAttribute("id", "main");
    el.removeAttribute("id");

    try std.testing.expect(el.getAttribute("id") == null);
}

test "removeAttribute on missing attribute is no-op" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const el = try doc.createElement("div");
    el.removeAttribute("nonexistent");

    try std.testing.expectEqual(@as(usize, 0), el.attributes.items.len);
}

test "hasAttribute returns true and false" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();

    const el = try doc.createElement("div");
    try el.setAttribute("data-x", "1");

    try std.testing.expect(el.hasAttribute("data-x"));
    try std.testing.expect(!el.hasAttribute("data-y"));
}
