const std = @import("std");
const event_dispatch = @import("../../src/js/event_dispatch.zig");
const EventDispatcher = event_dispatch.EventDispatcher;
const callback_registry = @import("../../src/js/callback_registry.zig");
const CallbackRegistry = callback_registry.CallbackRegistry;
const node_wrap = @import("../../src/js/node_wrap.zig");
const context_mod = @import("../../src/js/context.zig");
const dom = @import("../../src/dom/mod.zig");

// --- Mock bridge ----------------------------------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);
var call_function_count: u32 = 0;
var last_set_prop_name: ?[*:0]const u8 = null;
var mock_stopped_value: f64 = 0.0;
var stop_propagation_set: bool = false;

fn mockCreate() ?*anyopaque {
    return sentinel;
}
fn mockRelease(_: ?*anyopaque) void {}
fn mockEval(_: ?*anyopaque, _: [*]const u8, _: c_int) ?*anyopaque {
    return sentinel;
}
fn mockGlobal(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockMakeObj(_: ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xE000);
}
fn mockSetProp(_: ?*anyopaque, _: ?*anyopaque, name: [*:0]const u8, _: ?*anyopaque) void {
    last_set_prop_name = name;
    const prop = std.mem.span(name);
    if (std.mem.eql(u8, prop, "stopPropagation")) {
        stop_propagation_set = true;
    }
}
fn mockMakeFn(_: ?*anyopaque, _: [*:0]const u8, _: ?*const anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockMakeStr(_: ?*anyopaque, _: [*:0]const u8) ?*anyopaque {
    return @ptrFromInt(0xA000);
}
fn mockMakeUndef(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockValToStr(_: ?*anyopaque, _: ?*anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockStrGetUtf8(_: ?*anyopaque, _: [*]u8, _: c_int) c_int {
    return 0;
}
fn mockStrRelease(_: ?*anyopaque) void {}
fn mockValIsStr(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 0;
}
fn mockValueProtect(_: ?*anyopaque, _: ?*anyopaque) void {}
fn mockValueUnprotect(_: ?*anyopaque, _: ?*anyopaque) void {}
fn mockMakeClassInstance(_: ?*anyopaque, _: ?*anyopaque, _: ?*const anyopaque, _: ?*const anyopaque) ?*anyopaque {
    return @ptrFromInt(0xC100);
}
fn mockObjectGetPrivate(_: ?*anyopaque) ?*anyopaque {
    return null;
}
fn mockObjectGetProperty(_: ?*anyopaque, _: ?*anyopaque, name: [*:0]const u8) ?*anyopaque {
    const prop = std.mem.span(name);
    if (std.mem.eql(u8, prop, "_stopped")) {
        return @ptrFromInt(0xBEE1);
    }
    return @ptrFromInt(0xBEEF);
}
fn mockMakeNumberValue(_: ?*anyopaque, _: f64) ?*anyopaque {
    return @ptrFromInt(0xB000);
}
fn mockValueToNumber(_: ?*anyopaque, val: ?*anyopaque) f64 {
    // Return mock_stopped_value for the _stopped sentinel
    if (val == @as(?*anyopaque, @ptrFromInt(0xBEE1))) {
        return mock_stopped_value;
    }
    return 0.0;
}
fn mockValueIsNumber(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 1;
}
fn mockMakeNull(_: ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xD000);
}
fn mockCallFunction(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque, _: c_int, _: ?[*]const ?*anyopaque) ?*anyopaque {
    call_function_count += 1;
    return @ptrFromInt(0xBEEF);
}
fn mockClassGetUserData(_: ?*anyopaque) ?*anyopaque {
    return null;
}
fn mockHasException(_: ?*anyopaque) c_int {
    return 0;
}

const mock_bridge = context_mod.JsBridge{
    .context_create = mockCreate,
    .context_release = mockRelease,
    .evaluate_script = mockEval,
    .global_object = mockGlobal,
    .make_object = mockMakeObj,
    .object_set_property = mockSetProp,
    .make_function = mockMakeFn,
    .make_string_value = mockMakeStr,
    .make_undefined = mockMakeUndef,
    .value_to_string = mockValToStr,
    .string_get_utf8 = mockStrGetUtf8,
    .string_release = mockStrRelease,
    .value_is_string = mockValIsStr,
    .value_protect = &mockValueProtect,
    .value_unprotect = &mockValueUnprotect,
    .make_class_instance = &mockMakeClassInstance,
    .object_get_private = &mockObjectGetPrivate,
    .object_get_property = &mockObjectGetProperty,
    .make_number_value = &mockMakeNumberValue,
    .value_to_number = &mockValueToNumber,
    .value_is_number = &mockValueIsNumber,
    .make_null = &mockMakeNull,
    .call_function = &mockCallFunction,
    .class_get_user_data = &mockClassGetUserData,
    .has_exception = &mockHasException,
};

fn resetState() void {
    call_function_count = 0;
    last_set_prop_name = null;
    mock_stopped_value = 0.0;
    stop_propagation_set = false;
}

/// Free all duped event_type strings and the listeners list itself.
fn freeListeners(alloc: std.mem.Allocator, et: *dom.EventTarget) void {
    for (et.listeners.items) |listener| {
        alloc.free(listener.event_type);
    }
    et.listeners.deinit(alloc);
}

// --- Tests ----------------------------------------------------------------------

test "createEvent sets correct properties" {
    resetState();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var cb_reg = CallbackRegistry.init(alloc);
    defer cb_reg.deinit(&js_ctx);
    var node_reg = node_wrap.NodeRegistry.init(alloc);
    defer node_reg.deinit();

    var dispatcher = EventDispatcher.init(&js_ctx, &cb_reg, &node_reg);

    var node = dom.Node.init(alloc, .element);
    node.tag_name_str = "div";

    const event_obj = dispatcher.createEvent("click", &node);
    // createEvent should return a non-null JS object
    try std.testing.expect(event_obj != null);
}

test "dispatchEvent fires target listener" {
    resetState();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var cb_reg = CallbackRegistry.init(alloc);
    defer cb_reg.deinit(&js_ctx);
    var node_reg = node_wrap.NodeRegistry.init(alloc);
    defer node_reg.deinit();

    // Register a callback
    const fn_handle: context_mod.JsHandle = @ptrFromInt(0x5001);
    const cb_id = try cb_reg.register(&js_ctx, fn_handle);

    // Create a node and add an event listener
    var node = dom.Node.init(alloc, .element);
    defer freeListeners(alloc, &node.event_target);
    try node.event_target.addEventListener(alloc, "click", cb_id);

    var dispatcher = EventDispatcher.init(&js_ctx, &cb_reg, &node_reg);
    _ = dispatcher.dispatchEvent(&node, "click");

    try std.testing.expectEqual(@as(u32, 1), call_function_count);
}

test "dispatchEvent bubbles to parent" {
    resetState();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var cb_reg = CallbackRegistry.init(alloc);
    defer cb_reg.deinit(&js_ctx);
    var node_reg = node_wrap.NodeRegistry.init(alloc);
    defer node_reg.deinit();

    // Register callbacks for child and parent
    const fn1: context_mod.JsHandle = @ptrFromInt(0x6001);
    const fn2: context_mod.JsHandle = @ptrFromInt(0x6002);
    const child_cb = try cb_reg.register(&js_ctx, fn1);
    const parent_cb = try cb_reg.register(&js_ctx, fn2);

    // Set up parent-child relationship
    var parent_node = dom.Node.init(alloc, .element);
    defer freeListeners(alloc, &parent_node.event_target);
    var child_node = dom.Node.init(alloc, .element);
    defer freeListeners(alloc, &child_node.event_target);
    child_node.parent = &parent_node;

    try child_node.event_target.addEventListener(alloc, "click", child_cb);
    try parent_node.event_target.addEventListener(alloc, "click", parent_cb);

    var dispatcher = EventDispatcher.init(&js_ctx, &cb_reg, &node_reg);
    _ = dispatcher.dispatchEvent(&child_node, "click");

    // Both child and parent listeners should fire
    try std.testing.expectEqual(@as(u32, 2), call_function_count);
}

test "dispatchEvent skips non-matching event types" {
    resetState();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var cb_reg = CallbackRegistry.init(alloc);
    defer cb_reg.deinit(&js_ctx);
    var node_reg = node_wrap.NodeRegistry.init(alloc);
    defer node_reg.deinit();

    // Register a callback for "mouseover"
    const fn_handle: context_mod.JsHandle = @ptrFromInt(0x7001);
    const cb_id = try cb_reg.register(&js_ctx, fn_handle);

    var node = dom.Node.init(alloc, .element);
    defer freeListeners(alloc, &node.event_target);
    try node.event_target.addEventListener(alloc, "mouseover", cb_id);

    var dispatcher = EventDispatcher.init(&js_ctx, &cb_reg, &node_reg);
    _ = dispatcher.dispatchEvent(&node, "click");

    // No listeners should fire since types do not match
    try std.testing.expectEqual(@as(u32, 0), call_function_count);
}

test "dispatchEvent respects propagation stopped flag" {
    resetState();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var cb_reg = CallbackRegistry.init(alloc);
    defer cb_reg.deinit(&js_ctx);
    var node_reg = node_wrap.NodeRegistry.init(alloc);
    defer node_reg.deinit();

    const fn1: context_mod.JsHandle = @ptrFromInt(0x8001);
    const fn2: context_mod.JsHandle = @ptrFromInt(0x8002);
    const child_cb = try cb_reg.register(&js_ctx, fn1);
    const parent_cb = try cb_reg.register(&js_ctx, fn2);

    var parent_node = dom.Node.init(alloc, .element);
    defer freeListeners(alloc, &parent_node.event_target);
    var child_node = dom.Node.init(alloc, .element);
    defer freeListeners(alloc, &child_node.event_target);
    child_node.parent = &parent_node;

    try child_node.event_target.addEventListener(alloc, "click", child_cb);
    try parent_node.event_target.addEventListener(alloc, "click", parent_cb);

    var dispatcher = EventDispatcher.init(&js_ctx, &cb_reg, &node_reg);

    // Mock will return non-zero for _stopped after child fires
    mock_stopped_value = 1.0;
    defer {
        mock_stopped_value = 0.0;
    }
    _ = dispatcher.dispatchEvent(&child_node, "click");

    // Only the child listener should fire; parent is skipped
    try std.testing.expectEqual(@as(u32, 1), call_function_count);
}

test "createEvent includes stopPropagation method" {
    resetState();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var cb_reg = CallbackRegistry.init(alloc);
    defer cb_reg.deinit(&js_ctx);
    var node_reg = node_wrap.NodeRegistry.init(alloc);
    defer node_reg.deinit();

    var dispatcher = EventDispatcher.init(&js_ctx, &cb_reg, &node_reg);

    var node = dom.Node.init(alloc, .element);
    _ = dispatcher.createEvent("click", &node);

    // Verify that stopPropagation was set as a property
    try std.testing.expect(stop_propagation_set);
}
