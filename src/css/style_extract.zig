const std = @import("std");
const dom = @import("../dom/mod.zig");
const css_parser = @import("parser.zig");
const selector_mod = @import("selector.zig");

/// Extract all stylesheets from <style> elements in the DOM tree.
/// Returns an allocated slice of Stylesheet structs. The caller
/// owns the returned slice and must free it with freeStylesheets
/// or, if using an arena allocator, let the arena handle cleanup.
pub fn extractStylesheets(
    allocator: std.mem.Allocator,
    root: *const dom.Node,
) ![]const css_parser.Stylesheet {
    var sheets = std.ArrayListUnmanaged(css_parser.Stylesheet){};
    errdefer sheets.deinit(allocator);

    try walkForStyles(allocator, root, &sheets);
    return try sheets.toOwnedSlice(allocator);
}

/// Free all memory associated with a slice of stylesheets returned
/// by extractStylesheets, including all nested rules, selectors,
/// declarations, and string data.
pub fn freeStylesheets(
    allocator: std.mem.Allocator,
    sheets: []const css_parser.Stylesheet,
) void {
    for (sheets) |sheet| {
        for (sheet.rules) |rule| {
            for (rule.selectors) |sel| {
                for (sel.components) |comp| {
                    if (comp.part.tag) |t| allocator.free(t);
                    if (comp.part.id) |i| allocator.free(i);
                    for (comp.part.classes) |c| allocator.free(c);
                    if (comp.part.classes.len > 0) allocator.free(comp.part.classes);
                }
                allocator.free(sel.components);
            }
            for (rule.declarations) |decl| {
                allocator.free(decl.property);
                allocator.free(decl.value);
            }
            allocator.free(rule.selectors);
            allocator.free(rule.declarations);
        }
        allocator.free(sheet.rules);
    }
    allocator.free(sheets);
}

fn walkForStyles(
    allocator: std.mem.Allocator,
    node: *const dom.Node,
    sheets: *std.ArrayListUnmanaged(css_parser.Stylesheet),
) !void {
    if (node.node_type == .element and node.tag == .style) {
        const css_text = try node.getTextContent(allocator);
        defer allocator.free(css_text);
        if (css_text.len > 0) {
            const sheet = try css_parser.Parser.parse(allocator, css_text);
            try sheets.append(allocator, sheet);
        }
        return;
    }
    for (node.children.items) |child| {
        try walkForStyles(allocator, child, sheets);
    }
}
