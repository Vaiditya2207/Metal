const std = @import("std");
const script_runner = @import("../../src/js/script_runner.zig");
const context_mod = @import("../../src/js/context.zig");
const builder = @import("../../src/dom/builder.zig");

// --- Mock bridge for executeScripts test -----------------------------------------

const sentinel: *anyopaque = @ptrFromInt(0xDEAD);

var mock_eval_count: u32 = 0;

fn mockCreate() ?*anyopaque {
    return sentinel;
}
fn mockRelease(_: ?*anyopaque) void {}
fn mockEval(_: ?*anyopaque, _: [*]const u8, _: c_int) ?*anyopaque {
    mock_eval_count += 1;
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

test "extractScripts finds script elements" {
    const allocator = std.testing.allocator;
    const doc = try builder.parseHTML(allocator, "<html><body><script>console.log(\"hi\")</script></body></html>");
    defer doc.deinit();
    const scripts = try script_runner.extractScripts(allocator, doc.root);
    defer script_runner.freeScripts(allocator, scripts);
    try std.testing.expectEqual(@as(usize, 1), scripts.len);
    try std.testing.expectEqualStrings("console.log(\"hi\")", scripts[0]);
}

test "extractScripts finds multiple scripts in order" {
    const allocator = std.testing.allocator;
    const doc = try builder.parseHTML(allocator, "<html><body><script>first</script><script>second</script></body></html>");
    defer doc.deinit();
    const scripts = try script_runner.extractScripts(allocator, doc.root);
    defer script_runner.freeScripts(allocator, scripts);
    try std.testing.expectEqual(@as(usize, 2), scripts.len);
    try std.testing.expectEqualStrings("first", scripts[0]);
    try std.testing.expectEqualStrings("second", scripts[1]);
}

test "extractScripts returns empty for no scripts" {
    const allocator = std.testing.allocator;
    const doc = try builder.parseHTML(allocator, "<html><body><p>hello</p></body></html>");
    defer doc.deinit();
    const scripts = try script_runner.extractScripts(allocator, doc.root);
    defer script_runner.freeScripts(allocator, scripts);
    try std.testing.expectEqual(@as(usize, 0), scripts.len);
}

test "extractScripts skips empty scripts" {
    const allocator = std.testing.allocator;
    const doc = try builder.parseHTML(allocator, "<html><body><script></script></body></html>");
    defer doc.deinit();
    const scripts = try script_runner.extractScripts(allocator, doc.root);
    defer script_runner.freeScripts(allocator, scripts);
    try std.testing.expectEqual(@as(usize, 0), scripts.len);
}

test "executeScripts calls evaluateScript for each script" {
    const allocator = std.testing.allocator;
    mock_eval_count = 0;
    var ctx = try context_mod.JsContext.init(allocator, &mock_bridge);
    defer ctx.deinit();
    const scripts = [_][]const u8{ "alert(1)", "alert(2)", "alert(3)" };
    script_runner.executeScripts(&ctx, &scripts);
    try std.testing.expectEqual(@as(u32, 3), mock_eval_count);
}
