const std = @import("std");
const node_event_methods = @import("../../src/js/node_event_methods.zig");
const callback_registry = @import("../../src/js/callback_registry.zig");
const CallbackRegistry = callback_registry.CallbackRegistry;
const node_wrap = @import("../../src/js/node_wrap.zig");
const context_mod = @import("../../src/js/context.zig");
const dom = @import("../../src/dom/mod.zig");

// --- Mock bridge ----------------------------------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);
var mock_str_content: []const u8 = "click";
var protect_count: u32 = 0;

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
    return sentinel;
}
fn mockSetProp(_: ?*anyopaque, _: ?*anyopaque, _: [*:0]const u8, _: ?*anyopaque) void {}
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
    return @ptrFromInt(0xE000);
}
fn mockStrGetUtf8(_: ?*anyopaque, buf: [*]u8, max_len: c_int) c_int {
    const src = mock_str_content;
    const copy_len = @min(src.len, @as(usize, @intCast(max_len)) -| 1);
    for (src[0..copy_len], 0..) |c, i| {
        buf[i] = c;
    }
    buf[copy_len] = 0;
    return @intCast(copy_len + 1);
}
fn mockStrRelease(_: ?*anyopaque) void {}
fn mockValIsStr(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 0;
}
fn mockValueProtect(_: ?*anyopaque, _: ?*anyopaque) void {
    protect_count += 1;
}
fn mockValueUnprotect(_: ?*anyopaque, _: ?*anyopaque) void {}
fn mockMakeClassInstance(_: ?*anyopaque, _: ?*anyopaque, _: ?*const anyopaque, _: ?*const anyopaque) ?*anyopaque {
    return @ptrFromInt(0xC100);
}
fn mockObjectGetPrivate(obj: ?*anyopaque) ?*anyopaque {
    return obj;
}
fn mockObjectGetProperty(_: ?*anyopaque, _: ?*anyopaque, _: [*:0]const u8) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockMakeNumberValue(_: ?*anyopaque, _: f64) ?*anyopaque {
    return @ptrFromInt(0xB000);
}
fn mockValueToNumber(_: ?*anyopaque, _: ?*anyopaque) f64 {
    return 0.0;
}
fn mockValueIsNumber(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 0;
}
fn mockMakeNull(_: ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xD000);
}
fn mockCallFunction(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque, _: c_int, _: ?[*]const ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockClassGetUserData(obj: ?*anyopaque) ?*anyopaque {
    return obj;
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
    mock_str_content = "click";
    protect_count = 0;
    node_event_methods.resetGlobal();
}

// --- Tests ----------------------------------------------------------------------

test "jsAddEventListener registers callback and adds listener" {
    resetState();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var cb_reg = CallbackRegistry.init(alloc);
    defer cb_reg.deinit(&js_ctx);

    node_event_methods.setGlobal(&js_ctx, &cb_reg);

    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();
    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    mock_str_content = "click";
    const fn_handle: ?*anyopaque = @ptrFromInt(0x9001);
    const args = [_]?*anyopaque{ @ptrFromInt(0x8001), fn_handle };

    const result = node_event_methods.jsAddEventListener(
        js_ctx.ctx,
        null,
        @ptrCast(&node_ctx),
        2,
        @ptrCast(&args),
    );
    try std.testing.expect(result != null);
    try std.testing.expect(elem.event_target.hasListeners("click"));
    try std.testing.expectEqual(@as(u32, 1), cb_reg.count());
}

test "jsRemoveEventListener removes listener" {
    resetState();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var cb_reg = CallbackRegistry.init(alloc);
    defer cb_reg.deinit(&js_ctx);

    node_event_methods.setGlobal(&js_ctx, &cb_reg);

    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();
    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    mock_str_content = "click";
    const fn_handle: ?*anyopaque = @ptrFromInt(0x9002);
    const add_args = [_]?*anyopaque{ @ptrFromInt(0x8002), fn_handle };
    _ = node_event_methods.jsAddEventListener(
        js_ctx.ctx,
        null,
        @ptrCast(&node_ctx),
        2,
        @ptrCast(&add_args),
    );
    try std.testing.expect(elem.event_target.hasListeners("click"));

    const remove_args = [_]?*anyopaque{ @ptrFromInt(0x8002), fn_handle };
    _ = node_event_methods.jsRemoveEventListener(
        js_ctx.ctx,
        null,
        @ptrCast(&node_ctx),
        2,
        @ptrCast(&remove_args),
    );
    try std.testing.expect(!elem.event_target.hasListeners("click"));
}

test "jsAddEventListener returns undefined with no args" {
    resetState();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var cb_reg = CallbackRegistry.init(alloc);
    defer cb_reg.deinit(&js_ctx);

    node_event_methods.setGlobal(&js_ctx, &cb_reg);

    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    const result = node_event_methods.jsAddEventListener(
        js_ctx.ctx,
        null,
        @ptrCast(&node_ctx),
        0,
        null,
    );
    try std.testing.expect(result != null);
    try std.testing.expect(!elem.event_target.hasListeners("click"));
}
