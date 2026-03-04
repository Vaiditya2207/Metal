const std = @import("std");
const context = @import("context.zig");
const JsHandle = context.JsHandle;
const JsBridge = context.JsBridge;
const JsContext = context.JsContext;
const node_wrap = @import("node_wrap.zig");
const NodeContext = node_wrap.NodeContext;
const CallbackRegistry = @import("callback_registry.zig").CallbackRegistry;

// Module-level references set during initialization.
var g_js_ctx: ?*JsContext = null;
var g_callback_registry: ?*CallbackRegistry = null;

/// Wire the global references needed by event method callbacks.
pub fn setGlobal(js_ctx: *JsContext, registry: *CallbackRegistry) void {
    g_js_ctx = js_ctx;
    g_callback_registry = registry;
}

/// Reset global state (for tests).
pub fn resetGlobal() void {
    g_js_ctx = null;
    g_callback_registry = null;
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

/// Cast a raw pointer to NodeContext via class_get_user_data.
fn castNodeContext(ptr: ?*anyopaque) ?*NodeContext {
    const js_ctx = g_js_ctx orelse return null;
    const data = js_ctx.bridge.class_get_user_data(ptr);
    if (data == null) return null;
    return @ptrCast(@alignCast(data));
}

/// Read an argument from the args pointer at the given index.
fn readArg(arg_count: c_int, args: ?*const JsHandle, index: usize) ?JsHandle {
    if (args == null) return null;
    if (index >= @as(usize, @intCast(arg_count))) return null;
    const arg_slice: [*]const JsHandle = @ptrCast(args.?);
    return arg_slice[index];
}

/// JS-callable: node.addEventListener(type, callback)
pub fn jsAddEventListener(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;
    const registry = g_callback_registry orelse return bridge.make_undefined(ctx);
    const js_ctx = g_js_ctx orelse return bridge.make_undefined(ctx);

    if (arg_count < 2) return bridge.make_undefined(ctx);
    const type_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    const fn_arg = readArg(arg_count, args, 1) orelse return bridge.make_undefined(ctx);

    var type_buf: [256]u8 = undefined;
    const event_type = readJsString(bridge, ctx, type_arg, &type_buf) orelse {
        return bridge.make_undefined(ctx);
    };

    const cb_id = registry.register(js_ctx, fn_arg) catch return bridge.make_undefined(ctx);
    node_ctx.node.event_target.addEventListener(node_ctx.node.allocator, event_type, cb_id) catch {
        registry.unregister(js_ctx, cb_id);
        return bridge.make_undefined(ctx);
    };

    return bridge.make_undefined(ctx);
}

/// JS-callable: node.removeEventListener(type, callback)
pub fn jsRemoveEventListener(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    this_obj: ?*anyopaque,
    arg_count: c_int,
    args: ?*const JsHandle,
) callconv(.c) ?*anyopaque {
    const node_ctx = castNodeContext(this_obj) orelse return null;
    const bridge = node_ctx.js_ctx.bridge;
    const registry = g_callback_registry orelse return bridge.make_undefined(ctx);
    const js_ctx = g_js_ctx orelse return bridge.make_undefined(ctx);

    if (arg_count < 2) return bridge.make_undefined(ctx);
    const type_arg = readArg(arg_count, args, 0) orelse return bridge.make_undefined(ctx);
    const fn_arg = readArg(arg_count, args, 1) orelse return bridge.make_undefined(ctx);

    var type_buf: [256]u8 = undefined;
    const event_type = readJsString(bridge, ctx, type_arg, &type_buf) orelse {
        return bridge.make_undefined(ctx);
    };

    const cb_id = registry.findIdByHandle(fn_arg) orelse return bridge.make_undefined(ctx);
    node_ctx.node.event_target.removeEventListener(event_type, cb_id);
    registry.unregister(js_ctx, cb_id);

    return bridge.make_undefined(ctx);
}
