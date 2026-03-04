const std = @import("std");
const context_mod = @import("../../src/js/context.zig");
const console_mod = @import("../../src/js/console.zig");

// --- Shared mock bridge ---------------------------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);

var mock_set_prop_count: u32 = 0;
var mock_make_fn_count: u32 = 0;

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
fn mockSetProp(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: [*:0]const u8,
    _: ?*anyopaque,
) void {
    mock_set_prop_count += 1;
}
fn mockMakeFn(
    _: ?*anyopaque,
    _: [*:0]const u8,
    _: ?*const anyopaque,
) ?*anyopaque {
    mock_make_fn_count += 1;
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
fn mockValueProtect(_: ?*anyopaque, _: ?*anyopaque) void {}
fn mockValueUnprotect(_: ?*anyopaque, _: ?*anyopaque) void {}
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
fn mockCallFunction(
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: c_int,
    _: ?[*]const ?*anyopaque,
) ?*anyopaque {
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
    mock_set_prop_count = 0;
    mock_make_fn_count = 0;
}

// --- Tests ----------------------------------------------------------------------

test "handleLogMessage appends to buffer" {
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    try console_mod.handleLogMessage(&ctx, "hello world");
    try std.testing.expectEqualStrings("hello world\n", ctx.getLogOutput());
}

test "handleLogMessage accumulates multiple messages" {
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    try console_mod.handleLogMessage(&ctx, "first");
    try console_mod.handleLogMessage(&ctx, "second");
    try std.testing.expectEqualStrings("first\nsecond\n", ctx.getLogOutput());
}

test "handleWarnMessage appends to buffer" {
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    try console_mod.handleWarnMessage(&ctx, "watch out");
    try std.testing.expectEqualStrings("watch out\n", ctx.getLogOutput());
}

test "handleErrorMessage appends to buffer" {
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    try console_mod.handleErrorMessage(&ctx, "something broke");
    try std.testing.expectEqualStrings("something broke\n", ctx.getLogOutput());
}

test "bindConsole sets properties on global for log warn and error" {
    resetCounters();
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    console_mod.bindConsole(&ctx, null, null, null);
    // bindConsole creates 3 functions (log, warn, error) and sets them on
    // console_obj, then sets console_obj on global = 4 set_property calls.
    try std.testing.expectEqual(@as(u32, 4), mock_set_prop_count);
    try std.testing.expectEqual(@as(u32, 3), mock_make_fn_count);
}

test "warn and error messages accumulate with log messages" {
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    try console_mod.handleLogMessage(&ctx, "info");
    try console_mod.handleWarnMessage(&ctx, "caution");
    try console_mod.handleErrorMessage(&ctx, "failure");
    try std.testing.expectEqualStrings(
        "info\ncaution\nfailure\n",
        ctx.getLogOutput(),
    );
}
