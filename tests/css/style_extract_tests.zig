const std = @import("std");
const dom = @import("../../src/dom/mod.zig");
const css = @import("../../src/css/mod.zig");

test "extractStylesheets finds style element CSS" {
    const html =
        \\<html><head><style>
        \\body { background-color: #000 }
        \\.main { color: red }
        \\</style></head><body><div class="main">Hello</div></body></html>
    ;
    const doc = try dom.parseHTML(std.testing.allocator, html);
    defer doc.deinit();

    const sheets = try css.extractStylesheets(std.testing.allocator, doc.root);
    defer css.freeStylesheets(std.testing.allocator, sheets);

    try std.testing.expectEqual(@as(usize, 1), sheets.len);
    try std.testing.expect(sheets[0].rules.len >= 2);
}

test "extractStylesheets returns empty for no style elements" {
    const html = "<html><body><p>No styles</p></body></html>";
    const doc = try dom.parseHTML(std.testing.allocator, html);
    defer doc.deinit();

    const sheets = try css.extractStylesheets(std.testing.allocator, doc.root);
    defer css.freeStylesheets(std.testing.allocator, sheets);

    try std.testing.expectEqual(@as(usize, 0), sheets.len);
}

test "extractStylesheets handles multiple style elements" {
    const html =
        \\<html><head>
        \\<style>h1 { font-size: 32px }</style>
        \\<style>p { color: blue }</style>
        \\</head><body></body></html>
    ;
    const doc = try dom.parseHTML(std.testing.allocator, html);
    defer doc.deinit();

    const sheets = try css.extractStylesheets(std.testing.allocator, doc.root);
    defer css.freeStylesheets(std.testing.allocator, sheets);

    try std.testing.expectEqual(@as(usize, 2), sheets.len);
}

test "extractStylesheets ignores empty style elements" {
    const html = "<html><head><style></style></head><body></body></html>";
    const doc = try dom.parseHTML(std.testing.allocator, html);
    defer doc.deinit();

    const sheets = try css.extractStylesheets(std.testing.allocator, doc.root);
    defer css.freeStylesheets(std.testing.allocator, sheets);

    try std.testing.expectEqual(@as(usize, 0), sheets.len);
}
