const std = @import("std");
const dom_bindings = @import("../../src/js/dom_bindings.zig");
const dom = @import("../../src/dom/mod.zig");

// -- helpers ------------------------------------------------------------------

fn makeDoc() !*dom.Document {
    return dom.Document.init(std.testing.allocator);
}

fn appendElement(doc: *dom.Document, parent: *dom.Node, tag: []const u8) !*dom.Node {
    const elem = try doc.createElement(tag);
    try parent.appendChild(elem, doc.limits);
    return elem;
}

// -- getElementById -----------------------------------------------------------

test "getElementById finds element by id attribute" {
    const doc = try makeDoc();
    defer doc.deinit();

    const div = try appendElement(doc, doc.root, "div");
    try div.setAttribute("id", "main");

    const result = dom_bindings.getElementById(doc.root, "main");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(div, result.?);
}

test "getElementById returns null for missing id" {
    const doc = try makeDoc();
    defer doc.deinit();

    _ = try appendElement(doc, doc.root, "div");

    const result = dom_bindings.getElementById(doc.root, "absent");
    try std.testing.expect(result == null);
}

test "getElementById finds nested element" {
    const doc = try makeDoc();
    defer doc.deinit();

    const outer = try appendElement(doc, doc.root, "div");
    const inner = try appendElement(doc, outer, "span");
    try inner.setAttribute("id", "deep");

    const result = dom_bindings.getElementById(doc.root, "deep");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(inner, result.?);
}

// -- getTextContent -----------------------------------------------------------

test "getTextContent returns text of single text child" {
    const doc = try makeDoc();
    defer doc.deinit();

    const div = try appendElement(doc, doc.root, "p");
    const txt = try doc.createTextNode("hello");
    try div.appendChild(txt, doc.limits);

    const content = try dom_bindings.getTextContent(div, std.testing.allocator);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("hello", content);
}

test "getTextContent concatenates nested text" {
    const doc = try makeDoc();
    defer doc.deinit();

    const div = try appendElement(doc, doc.root, "div");
    const t1 = try doc.createTextNode("ab");
    try div.appendChild(t1, doc.limits);
    const span = try appendElement(doc, div, "span");
    const t2 = try doc.createTextNode("cd");
    try span.appendChild(t2, doc.limits);

    const content = try dom_bindings.getTextContent(div, std.testing.allocator);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("abcd", content);
}

// -- setTextContent -----------------------------------------------------------

test "setTextContent replaces children" {
    const doc = try makeDoc();
    defer doc.deinit();

    const div = try appendElement(doc, doc.root, "div");
    const old = try doc.createTextNode("old");
    try div.appendChild(old, doc.limits);

    try dom_bindings.setTextContent(div, "new");

    const content = try dom_bindings.getTextContent(div, std.testing.allocator);
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("new", content);
    try std.testing.expectEqual(@as(usize, 1), div.children.items.len);
}

// -- getAttribute / setAttribute ----------------------------------------------

test "getAttribute returns attribute value" {
    const doc = try makeDoc();
    defer doc.deinit();

    const div = try appendElement(doc, doc.root, "div");
    try div.setAttribute("class", "main");

    const val = dom_bindings.getAttribute(div, "class");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("main", val.?);
}

test "getAttribute returns null for missing attribute" {
    const doc = try makeDoc();
    defer doc.deinit();

    const div = try appendElement(doc, doc.root, "div");
    const val = dom_bindings.getAttribute(div, "nonexistent");
    try std.testing.expect(val == null);
}

test "setAttribute sets a new attribute readable via getAttribute" {
    const doc = try makeDoc();
    defer doc.deinit();

    const div = try appendElement(doc, doc.root, "div");
    try dom_bindings.setAttribute(div, "data-x", "42");

    const val = dom_bindings.getAttribute(div, "data-x");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("42", val.?);
}

// -- getTagName ---------------------------------------------------------------

test "getTagName returns element tag name" {
    const doc = try makeDoc();
    defer doc.deinit();

    const div = try appendElement(doc, doc.root, "section");
    const name = dom_bindings.getTagName(div);
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("section", name.?);
}

test "getTagName returns null for text nodes" {
    const doc = try makeDoc();
    defer doc.deinit();

    const txt = try doc.createTextNode("hi");
    try doc.root.appendChild(txt, doc.limits);

    const name = dom_bindings.getTagName(txt);
    try std.testing.expect(name == null);
}
