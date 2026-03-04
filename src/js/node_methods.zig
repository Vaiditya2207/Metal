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
const pipeline = @import("pipeline.zig");

var g_bridge: ?*const JsBridge = null;

pub fn setBridge(bridge: *const JsBridge) void {
    g_bridge = bridge;
}

pub fn resetBridge() void {
    g_bridge = null;
}

/// Read a JS string argument into a provided buffer.
fn readJsString(bridge: *const JsBridge, ctx: JsHandle, value: JsHandle, buf: []u8) ?[]const u8 {
    const str_handle = bridge.value_to_string(ctx, value);
    if (str_handle == null) return null;
    defer bridge.string_release(str_handle);
    const len = bridge.string_get_utf8(str_handle, buf.ptr, @intCast(buf.len));
    if (len <= 0) return null;
    return buf[0..@intCast(len - 1)];
}

/// Cast a raw pointer to NodeContext via bridge's class_get_user_data.
fn castNodeContext(ptr: ?*anyopaque) ?*NodeContext {
    const bridge = g_bridge orelse return null;
    const data = bridge.class_get_user_data(ptr);
    if (data == null) return null;
    return @ptrCast(@alignCast(data));
}

/// Extract the NodeContext from a JS object handle via the bridge's class user data.
fn extractNodeContext(bridge: *const JsBridge, js_obj: ?*anyopaque) ?*NodeContext {
    const ptr = bridge.class_get_user_data(js_obj);
    if (ptr == null) return null;
    return @ptrCast(@alignCast(ptr));
}

/// Read an argument value from the args pointer at the given index.
fn readArg(arg_count: c_int, args: ?*const JsHandle, index: usize) ?JsHandle {
    if (args == null) return null;
    if (index >= @as(usize, @intCast(arg_count))) return null;
    const arg_slice: [*]const JsHandle = @ptrCast(args.?);
    return arg_slice[index];
}

/// JS-callable: node.appendChild(child)
pub fn jsAppendChild(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const child_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    const child_ctx = extractNodeContext(bridge, child_arg) orelse return bridge.make_undefined(ctx);

    const cfg = config.getConfig();
    const limits = .{
        .max_children = cfg.parser.max_children_per_node,
        .max_depth = cfg.parser.max_tree_depth,
    };
    node_ctx.node.appendChild(child_ctx.node, limits) catch return bridge.make_undefined(ctx);
    pipeline.notifyDirty();
    return child_arg;
}

/// JS-callable: node.removeChild(child)
pub fn jsRemoveChild(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const child_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    const child_ctx = extractNodeContext(bridge, child_arg) orelse return bridge.make_undefined(ctx);

    node_ctx.node.removeChild(child_ctx.node);
    pipeline.notifyDirty();
    return child_arg;
}

/// JS-callable: node.setAttribute(name, value)
pub fn jsSetAttribute(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    const value_arg = readArg(arg_count, args, 1) orelse return bridge.make_undefined(ctx);

    var name_buf: [256]u8 = undefined;
    var val_buf: [1024]u8 = undefined;
    const attr_name = readJsString(bridge, ctx, name_arg, &name_buf) orelse return bridge.make_undefined(ctx);
    const attr_val = readJsString(bridge, ctx, value_arg, &val_buf) orelse return bridge.make_undefined(ctx);

    node_ctx.node.setAttribute(attr_name, attr_val) catch return bridge.make_undefined(ctx);
    pipeline.notifyDirty();
    return bridge.make_undefined(ctx);
}

/// JS-callable: node.getAttribute(name)
pub fn jsGetAttribute(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_null(ctx);
    var name_buf: [256]u8 = undefined;
    const attr_name = readJsString(bridge, ctx, name_arg, &name_buf) orelse return bridge.make_null(ctx);

    const val = node_ctx.node.getAttribute(attr_name) orelse return bridge.make_null(ctx);

    var val_buf: [1024]u8 = undefined;
    if (val.len < val_buf.len) {
        @memcpy(val_buf[0..val.len], val);
        val_buf[val.len] = 0;
        return bridge.make_string_value(ctx, val_buf[0..val.len :0]);
    }
    return bridge.make_null(ctx);
}

/// JS-callable: node.removeAttribute(name)
pub fn jsRemoveAttribute(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    var name_buf: [256]u8 = undefined;
    const attr_name = readJsString(bridge, ctx, name_arg, &name_buf) orelse return bridge.make_undefined(ctx);

    node_ctx.node.removeAttribute(attr_name);
    pipeline.notifyDirty();
    return bridge.make_undefined(ctx);
}

/// JS-callable: node.hasAttribute(name)
pub fn jsHasAttribute(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;

    const name_arg = readArg(arg_count, args, 0) orelse return bridge.make_number_value(ctx, 0.0);
    var name_buf: [256]u8 = undefined;
    const attr_name = readJsString(bridge, ctx, name_arg, &name_buf) orelse {
        return bridge.make_number_value(ctx, 0.0);
    };

    const has = node_ctx.node.hasAttribute(attr_name);
    return bridge.make_number_value(ctx, if (has) 1.0 else 0.0);
}
