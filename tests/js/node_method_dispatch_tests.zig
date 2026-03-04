const std = @import("std");
const node_props = @import("../../src/js/node_props.zig");
const node_wrap = @import("../../src/js/node_wrap.zig");
const context_mod = @import("../../src/js/context.zig");
const dom = @import("../../src/dom/mod.zig");

// --- Mock bridge ----------------------------------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);
var last_string_made: ?[*:0]const u8 = null;
var last_number_made: f64 = 0;
var make_null_called: bool = false;
var make_fn_called: bool = false;
var last_fn_name: ?[*:0]const u8 = null;

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

fn mockMakeFn(_: ?*anyopaque, name: [*:0]const u8, _: ?*const anyopaque) ?*anyopaque {
    make_fn_called = true;
    last_fn_name = name;
    return @ptrFromInt(0xF000);
}

fn mockMakeStr(_: ?*anyopaque, name: [*:0]const u8) ?*anyopaque {
    last_string_made = name;
    return @ptrFromInt(0xA000);
}

fn mockMakeUndef(_: ?*anyopaque) ?*anyopaque {
    return sentinel;
}
fn mockValToStr(_: ?*anyopaque, _: ?*anyopaque) ?*anyopaque {
    return sentinel;
}

fn mockStrGetUtf8(_: ?*anyopaque, buf: [*]u8, max_len: c_int) c_int {
    const src = "mock";
    const len: usize = @intCast(@min(@as(c_int, @intCast(src.len + 1)), max_len));
    for (src[0..len -| 1], 0..) |c, i| {
        buf[i] = c;
    }
    if (len > 0) buf[len - 1] = 0;
    return @intCast(len);
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
fn mockObjectGetProperty(_: ?*anyopaque, _: ?*anyopaque, _: [*:0]const u8) ?*anyopaque {
    return @ptrFromInt(0xBEEF);
}

fn mockMakeNumberValue(_: ?*anyopaque, val: f64) ?*anyopaque {
    last_number_made = val;
    return @ptrFromInt(0xB000);
}

fn mockValueToNumber(_: ?*anyopaque, _: ?*anyopaque) f64 {
    return 0.0;
}
fn mockValueIsNumber(_: ?*anyopaque, _: ?*anyopaque) c_int {
    return 0;
}

fn mockMakeNull(_: ?*anyopaque) ?*anyopaque {
    make_null_called = true;
    return @ptrFromInt(0xD000);
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

// --- Helpers --------------------------------------------------------------------

fn makeTestNode() !struct { doc: *dom.Document, js_ctx: context_mod.JsContext, reg: node_wrap.NodeRegistry, elem: *dom.Node } {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    const elem = try doc.createElement("div");
    const js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    const reg = node_wrap.NodeRegistry.init(alloc);
    return .{ .doc = doc, .js_ctx = js_ctx, .reg = reg, .elem = elem };
}

fn callGetProperty(js_ctx: *context_mod.JsContext, reg: *node_wrap.NodeRegistry, elem: *dom.Node, name: [*:0]const u8) ?*anyopaque {
    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = reg,
        .js_ctx = js_ctx,
    };
    return node_props.nodeGetProperty(
        js_ctx.ctx,
        null,
        name,
        @ptrCast(&node_ctx),
    );
}

// --- Tests: nodeGetProperty returns functions for method names -------------------

test "nodeGetProperty returns function for appendChild" {
    var t = try makeTestNode();
    defer t.doc.deinit();
    defer t.js_ctx.deinit();
    defer t.reg.deinit();

    make_fn_called = false;
    last_fn_name = null;
    const result = callGetProperty(&t.js_ctx, &t.reg, t.elem, "appendChild");
    try std.testing.expect(result != null);
    try std.testing.expect(make_fn_called);
    try std.testing.expectEqualStrings("appendChild", std.mem.span(last_fn_name.?));
}

test "nodeGetProperty returns function for removeChild" {
    var t = try makeTestNode();
    defer t.doc.deinit();
    defer t.js_ctx.deinit();
    defer t.reg.deinit();

    make_fn_called = false;
    last_fn_name = null;
    const result = callGetProperty(&t.js_ctx, &t.reg, t.elem, "removeChild");
    try std.testing.expect(result != null);
    try std.testing.expect(make_fn_called);
    try std.testing.expectEqualStrings("removeChild", std.mem.span(last_fn_name.?));
}

test "nodeGetProperty returns function for setAttribute" {
    var t = try makeTestNode();
    defer t.doc.deinit();
    defer t.js_ctx.deinit();
    defer t.reg.deinit();

    make_fn_called = false;
    const result = callGetProperty(&t.js_ctx, &t.reg, t.elem, "setAttribute");
    try std.testing.expect(result != null);
    try std.testing.expect(make_fn_called);
}

test "nodeGetProperty returns function for getAttribute" {
    var t = try makeTestNode();
    defer t.doc.deinit();
    defer t.js_ctx.deinit();
    defer t.reg.deinit();

    make_fn_called = false;
    const result = callGetProperty(&t.js_ctx, &t.reg, t.elem, "getAttribute");
    try std.testing.expect(result != null);
    try std.testing.expect(make_fn_called);
}

test "nodeGetProperty returns function for addEventListener" {
    var t = try makeTestNode();
    defer t.doc.deinit();
    defer t.js_ctx.deinit();
    defer t.reg.deinit();

    make_fn_called = false;
    last_fn_name = null;
    const result = callGetProperty(&t.js_ctx, &t.reg, t.elem, "addEventListener");
    try std.testing.expect(result != null);
    try std.testing.expect(make_fn_called);
    try std.testing.expectEqualStrings("addEventListener", std.mem.span(last_fn_name.?));
}

test "nodeGetProperty returns function for removeEventListener" {
    var t = try makeTestNode();
    defer t.doc.deinit();
    defer t.js_ctx.deinit();
    defer t.reg.deinit();

    make_fn_called = false;
    last_fn_name = null;
    const result = callGetProperty(&t.js_ctx, &t.reg, t.elem, "removeEventListener");
    try std.testing.expect(result != null);
    try std.testing.expect(make_fn_called);
    try std.testing.expectEqualStrings("removeEventListener", std.mem.span(last_fn_name.?));
}

test "nodeGetProperty returns function for hasAttribute" {
    var t = try makeTestNode();
    defer t.doc.deinit();
    defer t.js_ctx.deinit();
    defer t.reg.deinit();

    make_fn_called = false;
    const result = callGetProperty(&t.js_ctx, &t.reg, t.elem, "hasAttribute");
    try std.testing.expect(result != null);
    try std.testing.expect(make_fn_called);
}

test "nodeGetProperty returns function for removeAttribute" {
    var t = try makeTestNode();
    defer t.doc.deinit();
    defer t.js_ctx.deinit();
    defer t.reg.deinit();

    make_fn_called = false;
    const result = callGetProperty(&t.js_ctx, &t.reg, t.elem, "removeAttribute");
    try std.testing.expect(result != null);
    try std.testing.expect(make_fn_called);
}
