const std = @import("std");
const context = @import("context.zig");
const JsHandle = context.JsHandle;
const JsBridge = context.JsBridge;
const JsContext = context.JsContext;
const node_wrap = @import("node_wrap.zig");
const NodeContext = node_wrap.NodeContext;
const node_mod = @import("../dom/node.zig");
const Node = node_mod.Node;
const config = @import("../config.zig");
const node_method_dispatch = @import("node_method_dispatch.zig");
const node_methods = @import("node_methods.zig");
const pipeline = @import("pipeline.zig");

/// Read a JS string value into a provided buffer. Returns the slice or null on failure.
fn readJsString(bridge: *const JsBridge, ctx: JsHandle, value: JsHandle, buf: []u8) ?[]const u8 {
    const str_handle = bridge.value_to_string(ctx, value);
    if (str_handle == null) return null;
    defer bridge.string_release(str_handle);
    const len = bridge.string_get_utf8(str_handle, buf.ptr, @intCast(buf.len));
    if (len <= 0) return null;
    return buf[0..@intCast(len - 1)];
}

/// Convert a Node's tag_name_str to uppercase into the provided buffer.
fn toUppercase(src: []const u8, buf: []u8) []const u8 {
    const copy_len = @min(src.len, buf.len);
    for (src[0..copy_len], 0..) |c, i| {
        buf[i] = std.ascii.toUpper(c);
    }
    return buf[0..copy_len];
}

/// Return the W3C nodeType integer for our internal NodeType.
fn nodeTypeNumber(node: *const Node) f64 {
    return switch (node.node_type) {
        .element => 1.0,
        .text => 3.0,
        .comment => 8.0,
        .document => 9.0,
        .doctype => 10.0,
    };
}

fn isMirroredAttributeProperty(prop: []const u8) bool {
    return std.mem.eql(u8, prop, "src") or
        std.mem.eql(u8, prop, "href") or
        std.mem.eql(u8, prop, "value") or
        std.mem.eql(u8, prop, "name") or
        std.mem.eql(u8, prop, "type") or
        std.mem.eql(u8, prop, "placeholder") or
        std.mem.eql(u8, prop, "rel") or
        std.mem.eql(u8, prop, "role") or
        std.mem.eql(u8, prop, "title") or
        std.mem.eql(u8, prop, "alt");
}

/// C-callable property getter invoked by the JSC trampoline.
pub fn nodeGetProperty(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    name: [*:0]const u8,
    private_data: ?*anyopaque,
) callconv(.c) ?*anyopaque {
    if (private_data == null) return null;
    const node_ctx: *NodeContext = @ptrCast(@alignCast(private_data));
    const node = node_ctx.node;
    const bridge = node_ctx.js_ctx.bridge;
    const prop = std.mem.span(name);

    if (std.mem.eql(u8, prop, "tagName") or std.mem.eql(u8, prop, "nodeName")) {
        return getTagNameValue(bridge, ctx, node);
    }
    if (std.mem.eql(u8, prop, "nodeType")) {
        return bridge.make_number_value(ctx, nodeTypeNumber(node));
    }
    if (std.mem.eql(u8, prop, "id")) {
        return getAttributeValue(bridge, ctx, node, "id");
    }
    if (std.mem.eql(u8, prop, "className")) {
        return getAttributeValue(bridge, ctx, node, "class");
    }
    if (std.mem.eql(u8, prop, "classList")) {
        return getClassListObject(bridge, ctx, node_ctx);
    }
    if (std.mem.eql(u8, prop, "style")) {
        return getStyleObject(bridge, ctx, node_ctx);
    }
    if (std.mem.eql(u8, prop, "textContent")) {
        return getTextContentValue(bridge, ctx, node);
    }
    if (std.mem.eql(u8, prop, "parentNode")) {
        return getParentValue(bridge, ctx, node_ctx);
    }
    if (std.mem.eql(u8, prop, "firstChild")) {
        return getFirstChildValue(bridge, ctx, node_ctx);
    }
    if (std.mem.eql(u8, prop, "lastChild")) {
        return getLastChildValue(bridge, ctx, node_ctx);
    }
    if (std.mem.eql(u8, prop, "data")) {
        return getDataValue(bridge, ctx, node);
    }
    if (node.node_type == .element and isMirroredAttributeProperty(prop)) {
        return getAttributeValue(bridge, ctx, node, prop);
    }
    if (node_method_dispatch.getMethodFunction(bridge, ctx, prop)) |method_fn| {
        return method_fn;
    }
    return null;
}

/// C-callable property setter invoked by the JSC trampoline.
pub fn nodeSetProperty(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    name: [*:0]const u8,
    value: ?*anyopaque,
    private_data: ?*anyopaque,
) callconv(.c) c_int {
    if (private_data == null) return 0;
    const node_ctx: *NodeContext = @ptrCast(@alignCast(private_data));
    const node = node_ctx.node;
    const bridge = node_ctx.js_ctx.bridge;
    const prop = std.mem.span(name);

    var buf: [1024]u8 = undefined;
    const str_val = readJsString(bridge, ctx, value, &buf) orelse return 0;

    if (std.mem.eql(u8, prop, "textContent")) {
        const cfg = config.getConfig();
        const limits = .{
            .max_children = cfg.parser.max_children_per_node,
            .max_depth = cfg.parser.max_tree_depth,
        };
        node.setTextContent(str_val, limits) catch return 0;
        pipeline.notifyDirty();
        return 1;
    }
    if (std.mem.eql(u8, prop, "id")) {
        node.setAttribute("id", str_val) catch return 0;
        pipeline.notifyDirty();
        return 1;
    }
    if (std.mem.eql(u8, prop, "className")) {
        node.setAttribute("class", str_val) catch return 0;
        pipeline.notifyDirty();
        return 1;
    }
    if (node.node_type == .element and isMirroredAttributeProperty(prop)) {
        node.setAttribute(prop, str_val) catch return 0;
        pipeline.notifyDirty();
        return 1;
    }
    return 0;
}

// --- Getter helpers -------------------------------------------------------------

fn getTagNameValue(bridge: *const JsBridge, ctx: JsHandle, node: *const Node) JsHandle {
    const tag_str = node.tag_name_str orelse return bridge.make_string_value(ctx, "");
    var upper_buf: [128]u8 = undefined;
    const upper = toUppercase(tag_str, &upper_buf);
    // Null-terminate for the bridge
    if (upper.len < upper_buf.len) {
        upper_buf[upper.len] = 0;
        return bridge.make_string_value(ctx, upper_buf[0..upper.len :0]);
    }
    return bridge.make_string_value(ctx, "");
}

fn getAttributeValue(bridge: *const JsBridge, ctx: JsHandle, node: *const Node, attr_name: []const u8) JsHandle {
    const val = node.getAttribute(attr_name) orelse return bridge.make_string_value(ctx, "");
    // We need a null-terminated copy
    var buf: [1024]u8 = undefined;
    if (val.len < buf.len) {
        @memcpy(buf[0..val.len], val);
        buf[val.len] = 0;
        return bridge.make_string_value(ctx, buf[0..val.len :0]);
    }
    return bridge.make_string_value(ctx, "");
}

fn getTextContentValue(bridge: *const JsBridge, ctx: JsHandle, node: *const Node) JsHandle {
    const content = node.getTextContent(node.allocator) catch return bridge.make_string_value(ctx, "");
    defer node.allocator.free(content);
    var buf: [4096]u8 = undefined;
    if (content.len < buf.len) {
        @memcpy(buf[0..content.len], content);
        buf[content.len] = 0;
        return bridge.make_string_value(ctx, buf[0..content.len :0]);
    }
    return bridge.make_string_value(ctx, "");
}

fn getParentValue(bridge: *const JsBridge, ctx: JsHandle, node_ctx: *NodeContext) JsHandle {
    const parent = node_ctx.node.parent orelse return bridge.make_null(ctx);
    const handle = node_wrap.wrapNode(node_ctx.js_ctx, node_ctx.registry, parent) catch {
        return bridge.make_null(ctx);
    };
    return handle;
}

fn getFirstChildValue(bridge: *const JsBridge, ctx: JsHandle, node_ctx: *NodeContext) JsHandle {
    if (node_ctx.node.children.items.len == 0) return bridge.make_null(ctx);
    const child = node_ctx.node.children.items[0];
    return node_wrap.wrapNode(node_ctx.js_ctx, node_ctx.registry, child) catch bridge.make_null(ctx);
}

fn getLastChildValue(bridge: *const JsBridge, ctx: JsHandle, node_ctx: *NodeContext) JsHandle {
    const items = node_ctx.node.children.items;
    if (items.len == 0) return bridge.make_null(ctx);
    const child = items[items.len - 1];
    return node_wrap.wrapNode(node_ctx.js_ctx, node_ctx.registry, child) catch bridge.make_null(ctx);
}

fn getDataValue(bridge: *const JsBridge, ctx: JsHandle, node: *const Node) JsHandle {
    const data = node.data orelse return bridge.make_null(ctx);
    var buf: [4096]u8 = undefined;
    if (data.len < buf.len) {
        @memcpy(buf[0..data.len], data);
        buf[data.len] = 0;
        return bridge.make_string_value(ctx, buf[0..data.len :0]);
    }
    return bridge.make_string_value(ctx, "");
}

fn getClassListObject(bridge: *const JsBridge, ctx: JsHandle, node_ctx: *NodeContext) JsHandle {
    const obj = bridge.make_object(ctx);
    if (obj == null) return bridge.make_null(ctx);
    const node_handle = node_wrap.wrapNode(node_ctx.js_ctx, node_ctx.registry, node_ctx.node) catch return bridge.make_null(ctx);
    bridge.object_set_property(ctx, obj, "__node", node_handle);
    bridge.object_set_property(ctx, obj, "contains", bridge.make_function(ctx, "contains", @ptrCast(&node_methods.jsClassListContains)));
    bridge.object_set_property(ctx, obj, "add", bridge.make_function(ctx, "add", @ptrCast(&node_methods.jsClassListAdd)));
    bridge.object_set_property(ctx, obj, "remove", bridge.make_function(ctx, "remove", @ptrCast(&node_methods.jsClassListRemove)));
    bridge.object_set_property(ctx, obj, "toggle", bridge.make_function(ctx, "toggle", @ptrCast(&node_methods.jsClassListToggle)));
    bridge.object_set_property(ctx, obj, "replace", bridge.make_function(ctx, "replace", @ptrCast(&node_methods.jsClassListReplace)));
    return obj;
}

fn getStyleObject(bridge: *const JsBridge, ctx: JsHandle, node_ctx: *NodeContext) JsHandle {
    const obj = bridge.make_object(ctx);
    if (obj == null) return bridge.make_null(ctx);
    const node_handle = node_wrap.wrapNode(node_ctx.js_ctx, node_ctx.registry, node_ctx.node) catch return bridge.make_null(ctx);
    bridge.object_set_property(ctx, obj, "__node", node_handle);
    bridge.object_set_property(ctx, obj, "setProperty", bridge.make_function(ctx, "setProperty", @ptrCast(&node_methods.jsStyleSetProperty)));
    bridge.object_set_property(ctx, obj, "getPropertyValue", bridge.make_function(ctx, "getPropertyValue", @ptrCast(&node_methods.jsStyleGetPropertyValue)));
    bridge.object_set_property(ctx, obj, "removeProperty", bridge.make_function(ctx, "removeProperty", @ptrCast(&node_methods.jsStyleRemoveProperty)));
    return obj;
}
