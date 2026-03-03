const std = @import("std");
const context_mod = @import("../../src/js/context.zig");
const console_mod = @import("../../src/js/console.zig");

// --- Shared mock bridge (reuses signatures from context_tests) -------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);

var mock_set_prop_count: u32 = 0;

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
fn mockSetProp(_: ?*anyopaque, _: ?*anyopaque, _: [*:0]const u8, _: ?*anyopaque) void {
    mock_set_prop_count += 1;
}
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
};

// --- Tests -----------------------------------------------------------------------

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

test "bindConsole sets properties on global" {
    mock_set_prop_count = 0;
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    console_mod.bindConsole(&ctx, null);
    // bindConsole should call object_set_property twice: once for "log" on
    // the console object and once for "console" on the global object.
    try std.testing.expectEqual(@as(u32, 2), mock_set_prop_count);
}
