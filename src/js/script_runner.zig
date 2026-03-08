const std = @import("std");
const node_mod = @import("../dom/node.zig");
const context_mod = @import("context.zig");

pub const Node = node_mod.Node;
pub const TagName = node_mod.TagName;

/// Extract inline script content from all <script> elements in document order.
/// Returns an array of script text strings. Caller owns the array and its strings.
pub fn extractScripts(allocator: std.mem.Allocator, root: *const Node) ![][]const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (list.items) |s| allocator.free(s);
        list.deinit(allocator);
    }
    try walkForScripts(allocator, root, &list);
    return try list.toOwnedSlice(allocator);
}

fn walkForScripts(
    allocator: std.mem.Allocator,
    node: *const Node,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    if (node.node_type == .element and node.tag == .script) {
        const text = try node.getTextContent(allocator);
        if (text.len > 0) {
            try out.append(allocator, text);
        } else {
            allocator.free(text);
        }
    }
    for (node.children.items) |child| {
        try walkForScripts(allocator, child, out);
    }
}

/// Free an array returned by extractScripts.
pub fn freeScripts(allocator: std.mem.Allocator, scripts: [][]const u8) void {
    for (scripts) |s| allocator.free(s);
    allocator.free(scripts);
}

/// Execute all extracted scripts in order via the JS context.
pub fn executeScripts(js_ctx: *context_mod.JsContext, scripts: []const []const u8) void {
    for (scripts, 0..) |script, idx| {
        _ = js_ctx.evaluateScript(script);
        if (js_ctx.hasException()) {
            var ex_buf: [2048]u8 = undefined;
            const preview_len = @min(script.len, 120);
            if (js_ctx.readExceptionString(&ex_buf)) |msg| {
                std.debug.print("[JS EXCEPTION][inline:{d}] {s} :: {s}\n", .{ idx, msg, script[0..preview_len] });
            } else {
                std.debug.print("[JS EXCEPTION][inline:{d}] {s}\n", .{ idx, script[0..preview_len] });
            }
            js_ctx.clearException();
        }
    }
}
