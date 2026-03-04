const std = @import("std");
const node_methods = @import("../../src/js/node_methods.zig");
const node_wrap = @import("../../src/js/node_wrap.zig");
const context_mod = @import("../../src/js/context.zig");
const dom = @import("../../src/dom/mod.zig");

// --- Mock bridge ----------------------------------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);
var last_string_made: ?[*:0]const u8 = null;

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
    return @ptrFromInt(0xE000);
}

/// The mock string_get_utf8 returns different strings based on a test-scoped variable.
var mock_str_content: []const u8 = "default";

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
fn mockValueProtect(_: ?*anyopaque, _: ?*anyopaque) void {}
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
    mock_str_content = "default";
    last_string_made = null;
    node_methods.resetBridge();
}

// --- Tests ----------------------------------------------------------------------

test "jsSetAttribute sets attribute on node" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    node_methods.setBridge(&mock_bridge);
    defer node_methods.resetBridge();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    mock_str_content = "42";
    const name_arg: ?*anyopaque = @ptrFromInt(0x1111);
    const value_arg: ?*anyopaque = @ptrFromInt(0x2222);
    const args = [_]?*anyopaque{ name_arg, value_arg };

    const result = node_methods.jsSetAttribute(
        js_ctx.ctx,
        null,
        @ptrCast(&node_ctx),
        2,
        @ptrCast(&args),
    );
    try std.testing.expect(result != null);
}

test "jsGetAttribute returns attribute value" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");
    try elem.setAttribute("data-x", "hello");

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    node_methods.setBridge(&mock_bridge);
    defer node_methods.resetBridge();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    mock_str_content = "data-x";
    const name_arg: ?*anyopaque = @ptrFromInt(0x3333);
    const args = [_]?*anyopaque{name_arg};

    last_string_made = null;
    const result = node_methods.jsGetAttribute(
        js_ctx.ctx,
        null,
        @ptrCast(&node_ctx),
        1,
        @ptrCast(&args),
    );
    try std.testing.expect(result != null);
    try std.testing.expect(last_string_made != null);
    const made_str = std.mem.span(last_string_made.?);
    try std.testing.expectEqualStrings("hello", made_str);
}

test "jsGetAttribute returns null for missing attribute" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    node_methods.setBridge(&mock_bridge);
    defer node_methods.resetBridge();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    mock_str_content = "nonexistent";
    const name_arg: ?*anyopaque = @ptrFromInt(0x3333);
    const args = [_]?*anyopaque{name_arg};

    const result = node_methods.jsGetAttribute(
        js_ctx.ctx,
        null,
        @ptrCast(&node_ctx),
        1,
        @ptrCast(&args),
    );
    try std.testing.expect(result != null);
}

test "jsRemoveAttribute removes attribute" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");
    try elem.setAttribute("data-x", "val");

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    node_methods.setBridge(&mock_bridge);
    defer node_methods.resetBridge();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    mock_str_content = "data-x";
    const name_arg: ?*anyopaque = @ptrFromInt(0x4444);
    const args = [_]?*anyopaque{name_arg};

    _ = node_methods.jsRemoveAttribute(
        js_ctx.ctx,
        null,
        @ptrCast(&node_ctx),
        1,
        @ptrCast(&args),
    );
    try std.testing.expect(!elem.hasAttribute("data-x"));
}

test "jsHasAttribute returns true for existing attribute" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const elem = try doc.createElement("div");
    try elem.setAttribute("data-x", "val");

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    node_methods.setBridge(&mock_bridge);
    defer node_methods.resetBridge();

    var node_ctx = node_wrap.NodeContext{
        .node = elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    mock_str_content = "data-x";
    const name_arg: ?*anyopaque = @ptrFromInt(0x5555);
    const args = [_]?*anyopaque{name_arg};

    const result = node_methods.jsHasAttribute(
        js_ctx.ctx,
        null,
        @ptrCast(&node_ctx),
        1,
        @ptrCast(&args),
    );
    try std.testing.expect(result != null);
}

test "jsAppendChild adds child to parent" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const parent_elem = try doc.createElement("div");
    try doc.root.appendChild(parent_elem, doc.limits);
    const child_elem = try doc.createElement("span");

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    node_methods.setBridge(&mock_bridge);
    defer node_methods.resetBridge();

    var parent_ctx = node_wrap.NodeContext{
        .node = parent_elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    var child_ctx = node_wrap.NodeContext{
        .node = child_elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    const args = [_]?*anyopaque{@ptrCast(&child_ctx)};

    const result = node_methods.jsAppendChild(
        js_ctx.ctx,
        null,
        @ptrCast(&parent_ctx),
        1,
        @ptrCast(&args),
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 1), parent_elem.children.items.len);
    try std.testing.expectEqual(child_elem, parent_elem.children.items[0]);
}

test "jsRemoveChild removes child from parent" {
    resetState();
    const alloc = std.testing.allocator;
    const doc = try dom.Document.init(alloc);
    defer doc.deinit();
    const parent_elem = try doc.createElement("div");
    try doc.root.appendChild(parent_elem, doc.limits);
    const child_elem = try doc.createElement("span");
    try parent_elem.appendChild(child_elem, doc.limits);
    try std.testing.expectEqual(@as(usize, 1), parent_elem.children.items.len);

    var js_ctx = try context_mod.JsContext.init(alloc, &mock_bridge);
    defer js_ctx.deinit();
    var reg = node_wrap.NodeRegistry.init(alloc);
    defer reg.deinit();

    node_methods.setBridge(&mock_bridge);
    defer node_methods.resetBridge();

    var parent_ctx = node_wrap.NodeContext{
        .node = parent_elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    var child_ctx = node_wrap.NodeContext{
        .node = child_elem,
        .registry = &reg,
        .js_ctx = &js_ctx,
    };

    const args = [_]?*anyopaque{@ptrCast(&child_ctx)};

    _ = node_methods.jsRemoveChild(
        js_ctx.ctx,
        null,
        @ptrCast(&parent_ctx),
        1,
        @ptrCast(&args),
    );
    try std.testing.expectEqual(@as(usize, 0), parent_elem.children.items.len);
}
