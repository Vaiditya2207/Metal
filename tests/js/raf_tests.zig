const std = @import("std");
const raf_mod = @import("../../src/js/raf.zig");
const RafQueue = raf_mod.RafQueue;
const context_mod = @import("../../src/js/context.zig");
const JsHandle = context_mod.JsHandle;

// --- Mock bridge ----------------------------------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);
var call_function_count: u32 = 0;
var protect_count: u32 = 0;
var unprotect_count: u32 = 0;
var last_timestamp_arg: f64 = 0.0;

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
fn mockMakeClassInstance(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*const anyopaque,
    _: ?*const anyopaque,
) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockObjectGetPrivate(_: ?*anyopaque) ?*anyopaque {
    return null;
}
fn mockObjectGetProperty(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: [*:0]const u8,
) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}
fn mockMakeNumberValue(_: ?*anyopaque, v: f64) ?*anyopaque {
    last_timestamp_arg = v;
    return @ptrFromInt(0xBEEF);
}
fn mockValueToNumber(_: ?*anyopaque, _: ?*anyopaque) f64 {
    return 0.0;
}
fn mockValueIsNumber(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 1;
}
fn mockMakeNull(_: ?*anyopaque) ?*anyopaque {
    return @ptrFromInt(0xD000);
}
fn mockCallFunction(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: c_int,
    _: ?[*]const ?*anyopaque,
) ?*anyopaque {
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

fn resetCounters() void {
    call_function_count = 0;
    protect_count = 0;
    unprotect_count = 0;
    last_timestamp_arg = 0.0;
}

// --- Tests ----------------------------------------------------------------------

test "requestAnimationFrame queues callback and returns incrementing id" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var rq = RafQueue.init(alloc, &js_ctx);
    defer rq.deinit();

    const cb: JsHandle = @ptrFromInt(0x1001);
    const id1 = try rq.requestAnimationFrame(cb);
    const id2 = try rq.requestAnimationFrame(cb);

    try std.testing.expectEqual(@as(u32, 1), id1);
    try std.testing.expectEqual(@as(u32, 2), id2);
    try std.testing.expectEqual(@as(u32, 2), rq.pendingCount());
    try std.testing.expectEqual(@as(u32, 2), protect_count);
}

test "tick fires all queued callbacks" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var rq = RafQueue.init(alloc, &js_ctx);
    defer rq.deinit();

    const cb1: JsHandle = @ptrFromInt(0x2001);
    const cb2: JsHandle = @ptrFromInt(0x2002);
    _ = try rq.requestAnimationFrame(cb1);
    _ = try rq.requestAnimationFrame(cb2);

    rq.tick(16.67);

    try std.testing.expectEqual(@as(u32, 2), call_function_count);
    try std.testing.expectEqual(@as(u32, 2), unprotect_count);
}

test "cancelAnimationFrame prevents callback from firing" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var rq = RafQueue.init(alloc, &js_ctx);
    defer rq.deinit();

    const cb: JsHandle = @ptrFromInt(0x3001);
    const id = try rq.requestAnimationFrame(cb);
    rq.cancelAnimationFrame(id);

    rq.tick(16.67);

    try std.testing.expectEqual(@as(u32, 0), call_function_count);
    try std.testing.expectEqual(@as(u32, 1), unprotect_count);
}

test "tick clears queue after firing" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var rq = RafQueue.init(alloc, &js_ctx);
    defer rq.deinit();

    const cb: JsHandle = @ptrFromInt(0x4001);
    _ = try rq.requestAnimationFrame(cb);

    try std.testing.expectEqual(@as(u32, 1), rq.pendingCount());

    rq.tick(16.67);

    try std.testing.expectEqual(@as(u32, 0), rq.pendingCount());

    // Second tick should not fire anything
    rq.tick(33.34);
    try std.testing.expectEqual(@as(u32, 1), call_function_count);
}

test "multiple rAF callbacks fire in order" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var rq = RafQueue.init(alloc, &js_ctx);
    defer rq.deinit();

    const cb1: JsHandle = @ptrFromInt(0x5001);
    const cb2: JsHandle = @ptrFromInt(0x5002);
    const cb3: JsHandle = @ptrFromInt(0x5003);
    _ = try rq.requestAnimationFrame(cb1);
    _ = try rq.requestAnimationFrame(cb2);
    _ = try rq.requestAnimationFrame(cb3);

    try std.testing.expectEqual(@as(u32, 3), rq.pendingCount());

    rq.tick(16.67);

    try std.testing.expectEqual(@as(u32, 3), call_function_count);
    try std.testing.expectEqual(@as(u32, 0), rq.pendingCount());
}

test "deinit cleans up without crash" {
    resetCounters();
    const alloc = std.testing.allocator;
    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();

    var rq = RafQueue.init(alloc, &js_ctx);

    const cb1: JsHandle = @ptrFromInt(0x6001);
    const cb2: JsHandle = @ptrFromInt(0x6002);
    _ = try rq.requestAnimationFrame(cb1);
    _ = try rq.requestAnimationFrame(cb2);

    try std.testing.expectEqual(@as(u32, 2), protect_count);

    rq.deinit();

    try std.testing.expectEqual(@as(u32, 2), unprotect_count);
}
