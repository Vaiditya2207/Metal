const std = @import("std");
const context_mod = @import("../../src/js/context.zig");

// --- Mock bridge state -----------------------------------------------------------

var mock_create_called: bool = false;
var mock_release_called: bool = false;
var mock_eval_called: bool = false;

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);

fn mockContextCreate() ?*anyopaque {
    mock_create_called = true;
    return sentinel;
}

fn mockContextCreateNull() ?*anyopaque {
    return null;
}

fn mockContextRelease(_: ?*anyopaque) void {
    mock_release_called = true;
}

fn mockEvalScript(_: ?*anyopaque, _: [*]const u8, _: c_int) ?*anyopaque {
    mock_eval_called = true;
    return sentinel;
}

fn mockGlobalObject(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}

fn mockMakeObject(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}

fn mockSetProperty(_: ?*anyopaque, _: ?*anyopaque, _: [*:0]const u8, _: ?*anyopaque) void {}

fn mockMakeFunction(_: ?*anyopaque, _: [*:0]const u8, _: ?*const anyopaque) ?*anyopaque {
    return sentinel;
}

fn mockMakeStringValue(_: ?*anyopaque, _: [*:0]const u8) ?*anyopaque {
    return sentinel;
}

fn mockMakeUndefined(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}

fn mockValueToString(_: ?*anyopaque, _: ?*anyopaque) ?*anyopaque {
    return sentinel;
}

fn mockStringGetUtf8(_: ?*anyopaque, _: [*]u8, _: c_int) c_int {
    return 0;
}

fn mockStringRelease(_: ?*anyopaque) void {}

fn mockValueIsString(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 0;
}

const mock_bridge = context_mod.JsBridge{
    .context_create = mockContextCreate,
    .context_release = mockContextRelease,
    .evaluate_script = mockEvalScript,
    .global_object = mockGlobalObject,
    .make_object = mockMakeObject,
    .object_set_property = mockSetProperty,
    .make_function = mockMakeFunction,
    .make_string_value = mockMakeStringValue,
    .make_undefined = mockMakeUndefined,
    .value_to_string = mockValueToString,
    .string_get_utf8 = mockStringGetUtf8,
    .string_release = mockStringRelease,
    .value_is_string = mockValueIsString,
};

// --- Tests -----------------------------------------------------------------------

test "context init calls bridge create" {
    mock_create_called = false;
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    try std.testing.expect(mock_create_called);
    try std.testing.expect(ctx.ctx != null);
}

test "context deinit calls bridge release" {
    mock_release_called = false;
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    ctx.deinit();
    try std.testing.expect(mock_release_called);
}

test "context init fails on null handle" {
    const null_bridge = blk: {
        var b = mock_bridge;
        b.context_create = mockContextCreateNull;
        break :blk b;
    };
    const result = context_mod.JsContext.init(std.testing.allocator, &null_bridge);
    try std.testing.expectError(error.JsContextCreationFailed, result);
}

test "evaluateScript delegates to bridge" {
    mock_eval_called = false;
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    const result = ctx.evaluateScript("1+1");
    try std.testing.expect(mock_eval_called);
    try std.testing.expect(result != null);
}

test "globalObject delegates to bridge" {
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    const global = ctx.globalObject();
    try std.testing.expect(global != null);
}

test "appendLog and getLogOutput" {
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    try ctx.appendLog("hello");
    try std.testing.expectEqualStrings("hello\n", ctx.getLogOutput());
}

test "appendLog accumulates messages" {
    var ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    defer ctx.deinit();
    try ctx.appendLog("first");
    try ctx.appendLog("second");
    try std.testing.expectEqualStrings("first\nsecond\n", ctx.getLogOutput());
}
