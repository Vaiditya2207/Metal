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
    doc_obj: JsHandle,
};

var g_binding: ?*DocumentBinding = null;

pub fn resetBinding() void {
    g_binding = null;
}

pub fn updateDocument(doc: *Document) void {
    if (g_binding) |b| {
        b.doc = doc;
        refreshDocumentNodeProperties(b);
    }
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
    binding.* = .{
        .doc = doc,
        .registry = registry,
        .js_ctx = js_ctx,
        .allocator = allocator,
        .doc_obj = null,
    };
    g_binding = binding;
    const bridge = js_ctx.bridge;
    const ctx = js_ctx.ctx;
    const global = bridge.global_object(ctx);
    const doc_obj = bridge.make_object(ctx);
    binding.doc_obj = doc_obj;
    setMethod(bridge, ctx, doc_obj, "getElementById", @ptrCast(&jsGetElementById));
    setMethod(bridge, ctx, doc_obj, "getElementsByTagName", @ptrCast(&jsGetElementsByTagName));
    setMethod(bridge, ctx, doc_obj, "getElementsByClassName", @ptrCast(&jsGetElementsByClassName));
    setMethod(bridge, ctx, doc_obj, "querySelector", @ptrCast(&jsQuerySelector));
    setMethod(bridge, ctx, doc_obj, "querySelectorAll", @ptrCast(&jsQuerySelectorAll));
    setMethod(bridge, ctx, doc_obj, "createElement", @ptrCast(&jsCreateElement));
    setMethod(bridge, ctx, doc_obj, "createTextNode", @ptrCast(&jsCreateTextNode));
    const fonts_obj = bridge.make_object(ctx);
    setMethod(bridge, ctx, fonts_obj, "load", @ptrCast(&jsFontsLoad));
    bridge.object_set_property(ctx, doc_obj, "fonts", fonts_obj);
    refreshDocumentNodeProperties(binding);
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

fn findFirstByTag(node: *Node, tag: dom_node.TagName) ?*Node {
    if (node.node_type == .element and node.tag == tag) return node;
    for (node.children.items) |child| {
        if (findFirstByTag(child, tag)) |found| return found;
    }
    return null;
}

fn setDocumentNodeProperty(binding: *const DocumentBinding, name: [*:0]const u8, node: ?*Node) void {
    if (binding.doc_obj == null) return;
    const n = node orelse return;
    const bridge = binding.js_ctx.bridge;
    const ctx = binding.js_ctx.ctx;
    const value = wrapOrNull(binding, n);
    bridge.object_set_property(ctx, binding.doc_obj, name, value);
}

fn refreshDocumentNodeProperties(binding: *const DocumentBinding) void {
    const doc = binding.doc;
    const root = doc.root;
    const html = if (findFirstByTag(root, .html)) |n| n else root;
    const head = findFirstByTag(root, .head);
    const body = findFirstByTag(root, .body);

    setDocumentNodeProperty(binding, "documentElement", html);
    setDocumentNodeProperty(binding, "head", head);
    setDocumentNodeProperty(binding, "body", body);
}

fn parseSelector(binding: *const DocumentBinding, sel_str: []const u8) ?struct { Selector, std.heap.ArenaAllocator } {
    var arena = std.heap.ArenaAllocator.init(binding.allocator);
    const sel = Selector.parse(arena.allocator(), sel_str) catch {
        arena.deinit();
        return null;
    };
    return .{ sel, arena };
}

fn jsReturnThis(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    _: c_int,
    _: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    if (this_obj != null) return this_obj;
    const b = g_binding orelse return null;
    return b.js_ctx.bridge.make_undefined(ctx);
}

fn jsFontsLoad(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: c_int,
    _: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const b = g_binding orelse return null;
    const bridge = b.js_ctx.bridge;
    const js_ctx = b.js_ctx.ctx;

    const promise_like = bridge.make_object(js_ctx);
    setMethod(bridge, js_ctx, promise_like, "then", @ptrCast(&jsReturnThis));
    setMethod(bridge, js_ctx, promise_like, "catch", @ptrCast(&jsReturnThis));
    setMethod(bridge, js_ctx, promise_like, "finally", @ptrCast(&jsReturnThis));
    return promise_like;
}

fn appendNodeToList(binding: *const DocumentBinding, arr: JsHandle, count: *f64, node: *Node) void {
    const wrapped = node_wrap.wrapNode(binding.js_ctx, binding.registry, node) catch return;
    var idx_buf: [24]u8 = undefined;
    const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{@as(u32, @intFromFloat(count.*))}) catch return;
    idx_buf[@min(idx_str.len, idx_buf.len - 1)] = 0;
    const idx_z: [*:0]const u8 = idx_buf[0..@min(idx_str.len, idx_buf.len - 1) :0];
    binding.js_ctx.bridge.object_set_property(binding.js_ctx.ctx, arr, idx_z, wrapped);
    count.* += 1;
}

fn makeNodeList(binding: *const DocumentBinding) JsHandle {
    const bridge = binding.js_ctx.bridge;
    const ctx = binding.js_ctx.ctx;
    const arr = bridge.make_object(ctx);
    setMethod(bridge, ctx, arr, "forEach", @ptrCast(&jsNodeListForEach));
    setMethod(bridge, ctx, arr, "item", @ptrCast(&jsNodeListItem));
    return arr;
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

pub fn jsGetElementsByTagName(
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
    const tag = readFirstArg(b, arg_count, args, &buf) orelse return jsNull(b);

    const arr = makeNodeList(b);
    var count: f64 = 0;
    collectByTag(b, b.doc.root, tag, arr, &count);
    bridge.object_set_property(ctx, arr, "length", bridge.make_number_value(ctx, count));
    return arr;
}

pub fn jsGetElementsByClassName(
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
    const class_name = readFirstArg(b, arg_count, args, &buf) orelse return jsNull(b);

    const arr = makeNodeList(b);
    var count: f64 = 0;
    collectByClassName(b, b.doc.root, class_name, arr, &count);
    bridge.object_set_property(ctx, arr, "length", bridge.make_number_value(ctx, count));
    return arr;
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
    const arr = makeNodeList(b);
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
        appendNodeToList(binding, arr, count, node);
    }
    for (node.children.items) |child| {
        collectAll(binding, sel, child, arr, count);
    }
}

fn collectByTag(binding: *const DocumentBinding, node: *Node, tag: []const u8, arr: JsHandle, count: *f64) void {
    if (node.node_type == .element) {
        const matches = if (std.mem.eql(u8, tag, "*")) true else blk: {
            const tag_name = node.tag_name_str orelse break :blk false;
            break :blk std.ascii.eqlIgnoreCase(tag_name, tag);
        };
        if (matches) appendNodeToList(binding, arr, count, node);
    }
    for (node.children.items) |child| {
        collectByTag(binding, child, tag, arr, count);
    }
}

fn hasClass(node: *Node, class_name: []const u8) bool {
    const class_attr = node.getAttribute("class") orelse return false;
    var it = std.mem.tokenizeAny(u8, class_attr, " \t\r\n");
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, class_name)) return true;
    }
    return false;
}

fn collectByClassName(binding: *const DocumentBinding, node: *Node, class_name: []const u8, arr: JsHandle, count: *f64) void {
    if (node.node_type == .element and hasClass(node, class_name)) {
        appendNodeToList(binding, arr, count, node);
    }
    for (node.children.items) |child| {
        collectByClassName(binding, child, class_name, arr, count);
    }
}

pub fn jsNodeListForEach(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const b = g_binding orelse return null;
    const bridge = b.js_ctx.bridge;
    const js_ctx = b.js_ctx.ctx;
    if (arg_count < 1 or args == null or this_obj == null) return bridge.make_undefined(ctx);

    const arg_slice = args.?;
    const callback = arg_slice[0] orelse return bridge.make_undefined(ctx);
    const this_arg = if (arg_count > 1) arg_slice[1] else bridge.make_null(js_ctx);

    const length_val = bridge.object_get_property(js_ctx, this_obj, "length");
    if (bridge.value_is_number(js_ctx, length_val) == 0) return bridge.make_undefined(ctx);
    const length_num = bridge.value_to_number(js_ctx, length_val);
    const max_len: usize = if (length_num <= 0) 0 else @intFromFloat(length_num);

    var i: usize = 0;
    while (i < max_len) : (i += 1) {
        var idx_buf: [24]u8 = undefined;
        const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{i}) catch break;
        idx_buf[@min(idx_str.len, idx_buf.len - 1)] = 0;
        const idx_z: [*:0]const u8 = idx_buf[0..@min(idx_str.len, idx_buf.len - 1) :0];
        const item = bridge.object_get_property(js_ctx, this_obj, idx_z);
        if (item == null) continue;

        const index_val = bridge.make_number_value(js_ctx, @floatFromInt(i));
        var call_args = [_]JsHandle{ item, index_val, this_obj };
        _ = bridge.call_function(js_ctx, callback, this_arg, 3, @ptrCast(&call_args));
    }
    return bridge.make_undefined(ctx);
}

pub fn jsNodeListItem(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const b = g_binding orelse return null;
    const bridge = b.js_ctx.bridge;
    const js_ctx = b.js_ctx.ctx;
    if (this_obj == null) return bridge.make_null(ctx);
    if (arg_count < 1 or args == null) return bridge.make_null(ctx);

    const index_arg = args.?[0] orelse return bridge.make_null(ctx);
    if (bridge.value_is_number(js_ctx, index_arg) == 0) return bridge.make_null(ctx);
    const idx_num = bridge.value_to_number(js_ctx, index_arg);
    if (idx_num < 0) return bridge.make_null(ctx);
    const idx: usize = @intFromFloat(idx_num);

    var idx_buf: [24]u8 = undefined;
    const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{idx}) catch return bridge.make_null(ctx);
    idx_buf[@min(idx_str.len, idx_buf.len - 1)] = 0;
    const idx_z: [*:0]const u8 = idx_buf[0..@min(idx_str.len, idx_buf.len - 1) :0];
    const item = bridge.object_get_property(js_ctx, this_obj, idx_z);
    return item orelse bridge.make_null(ctx);
}
