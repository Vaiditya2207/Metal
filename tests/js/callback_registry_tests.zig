const std = @import("std");
const callback_registry = @import("../../src/js/callback_registry.zig");
const CallbackRegistry = callback_registry.CallbackRegistry;
const context_mod = @import("../../src/js/context.zig");

// --- Mock bridge ----------------------------------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);
var protect_count: u32 = 0;
var unprotect_count: u32 = 0;

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
    return sentinel;
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
fn mockValueProtect(_: ?*anyopaque, _: ?*anyopaque) void {
    protect_count += 1;
}
fn mockValueUnprotect(_: ?*anyopaque, _: ?*anyopaque) void {
    unprotect_count += 1;
}
fn mockMakeClassInstance(_: ?*anyopaque, _: ?*anyopaque, _: ?*const anyopaque, _: ?*const anyopaque) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockObjectGetPrivate(_: ?*anyopaque) ?*anyopaque {
    return null;
}
fn mockObjectGetProperty(_: ?*anyopaque, _: ?*anyopaque, _: [*:0]const u8) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockMakeNumberValue(_: ?*anyopaque, _: f64) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockValueToNumber(_: ?*anyopaque, _: ?*anyopaque) f64 {
    return 0.0;
}
fn mockValueIsNumber(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 0;
}
fn mockMakeNull(_: ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockCallFunction(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque, _: c_int, _: ?[*]const ?*anyopaque) ?*anyopaque {
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

fn resetCounters() void {
    protect_count = 0;
    unprotect_count = 0;
}

// --- Tests ----------------------------------------------------------------------

test "register returns incrementing ids" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var reg = CallbackRegistry.init(alloc);
    defer reg.deinit(&js_ctx);

    const fn1: context_mod.JsHandle = @ptrFromInt(0x1001);
    const fn2: context_mod.JsHandle = @ptrFromInt(0x1002);

    const id1 = try reg.register(&js_ctx, fn1);
    const id2 = try reg.register(&js_ctx, fn2);

    try std.testing.expectEqual(@as(u64, 1), id1);
    try std.testing.expectEqual(@as(u64, 2), id2);
    try std.testing.expectEqual(@as(u32, 2), protect_count);
}

test "get returns stored handle for valid id" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var reg = CallbackRegistry.init(alloc);
    defer reg.deinit(&js_ctx);

    const fn_handle: context_mod.JsHandle = @ptrFromInt(0x2001);
    const id = try reg.register(&js_ctx, fn_handle);

    const retrieved = reg.get(id);
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(fn_handle, retrieved.?);
}

test "get returns null for invalid id" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var reg = CallbackRegistry.init(alloc);
    defer reg.deinit(&js_ctx);

    const retrieved = reg.get(999);
    try std.testing.expect(retrieved == null);
}

test "unregister removes callback and unprotects" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var reg = CallbackRegistry.init(alloc);
    defer reg.deinit(&js_ctx);

    const fn_handle: context_mod.JsHandle = @ptrFromInt(0x3001);
    const id = try reg.register(&js_ctx, fn_handle);

    try std.testing.expectEqual(@as(u32, 1), reg.count());
    reg.unregister(&js_ctx, id);
    try std.testing.expectEqual(@as(u32, 0), reg.count());
    try std.testing.expect(reg.get(id) == null);
    try std.testing.expectEqual(@as(u32, 1), unprotect_count);
}

test "deinit unprotects all remaining callbacks" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var reg = CallbackRegistry.init(alloc);

    const fn1: context_mod.JsHandle = @ptrFromInt(0x4001);
    const fn2: context_mod.JsHandle = @ptrFromInt(0x4002);
    const fn3: context_mod.JsHandle = @ptrFromInt(0x4003);
    _ = try reg.register(&js_ctx, fn1);
    _ = try reg.register(&js_ctx, fn2);
    _ = try reg.register(&js_ctx, fn3);

    try std.testing.expectEqual(@as(u32, 3), reg.count());
    reg.deinit(&js_ctx);
    try std.testing.expectEqual(@as(u32, 3), unprotect_count);
}
