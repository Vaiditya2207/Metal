const std = @import("std");
const context = @import("context.zig");
const JsHandle = context.JsHandle;
const JsBridge = context.JsBridge;
const JsContext = context.JsContext;
const node_wrap = @import("node_wrap.zig");
const NodeRegistry = node_wrap.NodeRegistry;
const dom_node = @import("../dom/node.zig");
const Node = dom_node.Node;
const dom_doc = @import("../dom/document.zig");
const Document = dom_doc.Document;
const css_selector = @import("../css/selector.zig");
const Selector = css_selector.Selector;

pub const DocumentBinding = struct {
    doc: *Document,
    registry: *NodeRegistry,
    js_ctx: *JsContext,
    allocator: std.mem.Allocator,
};

var g_binding: ?*DocumentBinding = null;

pub fn resetBinding() void {
    g_binding = null;
}

pub fn freeBinding(allocator: std.mem.Allocator) void {
    if (g_binding) |b| {
        allocator.destroy(b);
        g_binding = null;
    }
}

pub fn registerDocument(
    js_ctx: *JsContext,
    doc: *Document,
    registry: *NodeRegistry,
    allocator: std.mem.Allocator,
) !void {
    const binding = try allocator.create(DocumentBinding);
    binding.* = .{ .doc = doc, .registry = registry, .js_ctx = js_ctx, .allocator = allocator };
    g_binding = binding;
    const bridge = js_ctx.bridge;
    const ctx = js_ctx.ctx;
    const global = bridge.global_object(ctx);
    const doc_obj = bridge.make_object(ctx);
    setMethod(bridge, ctx, doc_obj, "getElementById", @ptrCast(&jsGetElementById));
    setMethod(bridge, ctx, doc_obj, "querySelector", @ptrCast(&jsQuerySelector));
    setMethod(bridge, ctx, doc_obj, "querySelectorAll", @ptrCast(&jsQuerySelectorAll));
    setMethod(bridge, ctx, doc_obj, "createElement", @ptrCast(&jsCreateElement));
    setMethod(bridge, ctx, doc_obj, "createTextNode", @ptrCast(&jsCreateTextNode));
    bridge.object_set_property(ctx, global, "document", doc_obj);
}

fn setMethod(bridge: *const JsBridge, ctx: JsHandle, obj: JsHandle, name: [*:0]const u8, cb: ?*const anyopaque) void {
    bridge.object_set_property(ctx, obj, name, bridge.make_function(ctx, name, cb));
}

fn readJsString(bridge: *const JsBridge, ctx: JsHandle, value: JsHandle, buf: []u8) ?[]const u8 {
    const str_handle = bridge.value_to_string(ctx, value);
    if (str_handle == null) return null;
    defer bridge.string_release(str_handle);
    const len = bridge.string_get_utf8(str_handle, buf.ptr, @intCast(buf.len));
    if (len <= 0) return null;
    return buf[0..@intCast(len - 1)];
}

fn readFirstArg(binding: *const DocumentBinding, arg_count: c_int, args: ?[*]const ?*anyopaque, buf: []u8) ?[]const u8 {
    if (arg_count < 1) return null;
    const arg_slice = args orelse return null;
    return readJsString(binding.js_ctx.bridge, binding.js_ctx.ctx, arg_slice[0], buf);
}

fn jsNull(binding: *const DocumentBinding) ?*anyopaque {
    return binding.js_ctx.bridge.make_null(binding.js_ctx.ctx);
}

fn wrapOrNull(binding: *const DocumentBinding, node: *Node) ?*anyopaque {
    return node_wrap.wrapNode(binding.js_ctx, binding.registry, node) catch jsNull(binding);
}

fn parseSelector(binding: *const DocumentBinding, sel_str: []const u8) ?struct { Selector, std.heap.ArenaAllocator } {
    var arena = std.heap.ArenaAllocator.init(binding.allocator);
    const sel = Selector.parse(arena.allocator(), sel_str) catch {
        arena.deinit();
        return null;
    };
    return .{ sel, arena };
}

// --- Callback functions (callconv .c) -------------------------------------------

pub fn jsGetElementById(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const b = g_binding orelse return null;
    var buf: [256]u8 = undefined;
    const id = readFirstArg(b, arg_count, args, &buf) orelse return jsNull(b);
    const node = b.doc.root.getElementById(id) orelse return jsNull(b);
    return wrapOrNull(b, node);
}

pub fn jsQuerySelector(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const b = g_binding orelse return null;
    var buf: [256]u8 = undefined;
    const sel_str = readFirstArg(b, arg_count, args, &buf) orelse return jsNull(b);
    var parsed = parseSelector(b, sel_str) orelse return jsNull(b);
    defer parsed[1].deinit();
    const match = findFirst(b.doc.root, parsed[0]) orelse return jsNull(b);
    return wrapOrNull(b, match);
}

pub fn jsQuerySelectorAll(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const b = g_binding orelse return null;
    const bridge = b.js_ctx.bridge;
    const ctx = b.js_ctx.ctx;
    var buf: [256]u8 = undefined;
    const sel_str = readFirstArg(b, arg_count, args, &buf) orelse return jsNull(b);
    var parsed = parseSelector(b, sel_str) orelse return jsNull(b);
    defer parsed[1].deinit();
    const arr = bridge.make_object(ctx);
    var count: f64 = 0;
    collectAll(b, parsed[0], b.doc.root, arr, &count);
    bridge.object_set_property(ctx, arr, "length", bridge.make_number_value(ctx, count));
    return arr;
}

pub fn jsCreateElement(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const b = g_binding orelse return null;
    var buf: [256]u8 = undefined;
    const tag = readFirstArg(b, arg_count, args, &buf) orelse return jsNull(b);
    const node = b.doc.createElement(tag) catch return jsNull(b);
    return wrapOrNull(b, node);
}

pub fn jsCreateTextNode(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const b = g_binding orelse return null;
    var buf: [256]u8 = undefined;
    const text = readFirstArg(b, arg_count, args, &buf) orelse return jsNull(b);
    const node = b.doc.createTextNode(text) catch return jsNull(b);
    return wrapOrNull(b, node);
}

// --- DOM tree walking -----------------------------------------------------------

fn findFirst(node: *Node, sel: Selector) ?*Node {
    if (node.node_type == .element and sel.matchesNode(node)) return node;
    for (node.children.items) |child| {
        if (findFirst(child, sel)) |found| return found;
    }
    return null;
}

fn collectAll(binding: *const DocumentBinding, sel: Selector, node: *Node, arr: JsHandle, count: *f64) void {
    if (node.node_type == .element and sel.matchesNode(node)) {
        const wrapped = node_wrap.wrapNode(binding.js_ctx, binding.registry, node) catch return;
        var idx_buf: [16]u8 = undefined;
        const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{@as(u32, @intFromFloat(count.*))}) catch return;
        idx_buf[@min(idx_str.len, idx_buf.len - 1)] = 0;
        const idx_z: [*:0]const u8 = idx_buf[0..@min(idx_str.len, idx_buf.len - 1) :0];
        binding.js_ctx.bridge.object_set_property(binding.js_ctx.ctx, arr, idx_z, wrapped);
        count.* += 1;
    }
    for (node.children.items) |child| {
        collectAll(binding, sel, child, arr, count);
    }
}
