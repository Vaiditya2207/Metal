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

fn mockStrGetUtf8(str_handle: ?*anyopaque, buf: [*]u8, max_len: c_int) c_int {
    _ = str_handle;
    const src = "newtext";
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

fn makeTestContext() !struct { js_ctx: context_mod.JsContext, reg: node_wrap.NodeRegistry } {
    const js_ctx = try context_mod.JsContext.init(std.testing.allocator, &mock_bridge);
    const reg = node_wrap.NodeRegistry.init(std.testing.allocator);
    return .{ .js_ctx = js_ctx, .reg = reg };
}

// --- nodeGetProperty tests ------------------------------------------------------

test "nodeGetProperty returns tagName for element" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    last_string_made = null;
    const result = node_props.nodeGetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "tagName",
        @ptrCast(&node_ctx),
    );
    try std.testing.expect(result != null);
    try std.testing.expect(last_string_made != null);
    const made_str = std.mem.span(last_string_made.?);
    try std.testing.expectEqualStrings("DIV", made_str);
}

test "nodeGetProperty returns nodeType for element" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("p");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    last_number_made = 0;
    const result = node_props.nodeGetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "nodeType",
        @ptrCast(&node_ctx),
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(f64, 1.0), last_number_made);
}

test "nodeGetProperty returns nodeType 3 for text node" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const txt = try doc.createTextNode("hello");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = txt,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    last_number_made = 0;
    _ = node_props.nodeGetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "nodeType",
        @ptrCast(&node_ctx),
    );
    try std.testing.expectEqual(@as(f64, 3.0), last_number_made);
}

test "nodeGetProperty returns id from attribute" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");
    try elem.setAttribute("id", "main");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    last_string_made = null;
    const result = node_props.nodeGetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "id",
        @ptrCast(&node_ctx),
    );
    try std.testing.expect(result != null);
    const made_str = std.mem.span(last_string_made.?);
    try std.testing.expectEqualStrings("main", made_str);
}

test "nodeGetProperty returns className from class attribute" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");
    try elem.setAttribute("class", "container");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    last_string_made = null;
    const result = node_props.nodeGetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "className",
        @ptrCast(&node_ctx),
    );
    try std.testing.expect(result != null);
    const made_str = std.mem.span(last_string_made.?);
    try std.testing.expectEqualStrings("container", made_str);
}

test "nodeGetProperty returns null for parentNode of root" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    make_null_called = false;
    const result = node_props.nodeGetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "parentNode",
        @ptrCast(&node_ctx),
    );
    // Should return the null JS value for a detached node
    try std.testing.expect(result != null);
    try std.testing.expect(make_null_called);
}

test "nodeGetProperty returns null for unknown property" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    const result = node_props.nodeGetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "nonexistentProp",
        @ptrCast(&node_ctx),
    );
    try std.testing.expect(result == null);
}

test "nodeGetProperty returns data for text node" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const txt = try doc.createTextNode("hello world");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = txt,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    last_string_made = null;
    const result = node_props.nodeGetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "data",
        @ptrCast(&node_ctx),
    );
    try std.testing.expect(result != null);
    const made_str = std.mem.span(last_string_made.?);
    try std.testing.expectEqualStrings("hello world", made_str);
}

// --- nodeSetProperty tests ------------------------------------------------------

test "nodeSetProperty sets textContent" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");
    try doc.root.appendChild(elem, doc.limits);

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    const handled = node_props.nodeSetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "textContent",
        @ptrFromInt(0x1234), // mock JS value
        @ptrCast(&node_ctx),
    );
    try std.testing.expectEqual(@as(c_int, 1), handled);
    // Verify textContent was actually set on the node
    const content = try elem.getTextContent(alloc);
    defer alloc.free(content);
    try std.testing.expectEqualStrings("newtext", content);
}

test "nodeSetProperty sets id attribute" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    const handled = node_props.nodeSetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "id",
        @ptrFromInt(0x1234),
        @ptrCast(&node_ctx),
    );
    try std.testing.expectEqual(@as(c_int, 1), handled);
    const id_val = elem.getAttribute("id");
    try std.testing.expect(id_val != null);
    try std.testing.expectEqualStrings("newtext", id_val.?);
}

test "nodeSetProperty sets className attribute" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    const handled = node_props.nodeSetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "className",
        @ptrFromInt(0x1234),
        @ptrCast(&node_ctx),
    );
    try std.testing.expectEqual(@as(c_int, 1), handled);
    const class_val = elem.getAttribute("class");
    try std.testing.expect(class_val != null);
    try std.testing.expectEqualStrings("newtext", class_val.?);
}

test "nodeSetProperty returns 0 for unknown property" {
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var ctx_and_reg = try makeTestContext();
    defer ctx_and_reg.js_ctx.deinit();
    defer ctx_and_reg.reg.deinit();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &ctx_and_reg.reg,
        .js_ctx = &ctx_and_reg.js_ctx,
    };

    const handled = node_props.nodeSetProperty(
        ctx_and_reg.js_ctx.ctx,
        null,
        "unknownProp",
        @ptrFromInt(0x1234),
        @ptrCast(&node_ctx),
    );
    try std.testing.expectEqual(@as(c_int, 0), handled);
}
