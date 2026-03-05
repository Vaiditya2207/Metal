const std = @import("std");
const testing = std.testing;
const dom = @import("../../src/dom/mod.zig");
const net = @import("../../src/net/mod.zig");

// Helper to build a basic DOM tree for testing
fn buildTestDom(doc: *dom.Document) !*dom.Node {
    const html = try doc.createElement("html");
    const head = try doc.createElement("head");
    const body = try doc.createElement("body");

    // <link rel="stylesheet" href="style.css">
    const link = try doc.createElement("link");
    try link.setAttribute("rel", "stylesheet");
    try link.setAttribute("href", "style.css");
    try head.appendChild(link, .{ .max_children = 1000, .max_depth = 1000 });

    // <script src="app.js"></script>
    const script = try doc.createElement("script");
    try script.setAttribute("src", "app.js");
    try head.appendChild(script, .{ .max_children = 1000, .max_depth = 1000 });

    // <img src="logo.png">
    const img = try doc.createElement("img");
    try img.setAttribute("src", "logo.png");
    try body.appendChild(img, .{ .max_children = 1000, .max_depth = 1000 });

    try html.appendChild(head, .{ .max_children = 1000, .max_depth = 1000 });
    try html.appendChild(body, .{ .max_children = 1000, .max_depth = 1000 });
    
    return html;
}

// Dummy fetch client that always returns empty 200
const dummy_bridge = net.fetch.NetBridge{
    .net_fetch_start = @ptrCast(&struct { fn start(a: [*:0]const u8, b: [*:0]const u8, c: ?[*]const ?[*:0]const u8, d: c_int, e: ?[*]const u8, f: c_int) callconv(.c) net.fetch.FetchHandle { _ = a; _ = b; _ = c; _ = d; _ = e; _ = f; return @ptrFromInt(1); } }.start),
    .net_fetch_poll = @ptrCast(&struct { fn poll(h: net.fetch.FetchHandle) callconv(.c) net.fetch.FetchStatus { _ = h; return .SUCCESS; } }.poll),
    .net_fetch_get_status_code = @ptrCast(&struct { fn code(h: net.fetch.FetchHandle) callconv(.c) c_int { _ = h; return 200; } }.code),
    .net_fetch_get_body = @ptrCast(&struct { fn body(h: net.fetch.FetchHandle, l: *c_int) callconv(.c) ?[*]const u8 { _ = h; l.* = 0; return null; } }.body),
    .net_fetch_free = @ptrCast(&struct { fn free(h: net.fetch.FetchHandle) callconv(.c) void { _ = h; } }.free),
    .net_fetch_get_header = @ptrCast(&struct { fn f(_: net.fetch.FetchHandle, _: [*:0]const u8, _: [*]u8, _: c_int) callconv(.c) c_int { return 0; } }.f),
    .net_fetch_get_header_count = @ptrCast(&struct { fn f(_: net.fetch.FetchHandle) callconv(.c) c_int { return 0; } }.f),
    .net_fetch_get_header_at = @ptrCast(&struct { fn f(_: net.fetch.FetchHandle, _: c_int, _: [*]u8, _: c_int, _: [*]u8, _: c_int) callconv(.c) c_int { return 0; } }.f),
};

test "ResourceLoader discoverResources" {
    var doc = try dom.Document.init(testing.allocator);
    defer doc.deinit();

    const root = try buildTestDom(doc);

    var client = net.fetch.FetchClient.init(testing.allocator, &dummy_bridge);
    const base_url = try net.url.Url.parse("http://example.com/");
    
    var loader = net.loader.ResourceLoader.init(testing.allocator, &client, base_url);
    const refs = try loader.discoverResources(root);
    defer testing.allocator.free(refs);
    defer for (refs) |ref| testing.allocator.free(ref.url);

    try testing.expectEqual(@as(usize, 3), refs.len);
    
    // Order based on DOM traversal
    try testing.expectEqualStrings("http://example.com/style.css", refs[0].url);
    try testing.expectEqual(net.loader.ResourceType.CSS, refs[0].type);

    try testing.expectEqualStrings("http://example.com/app.js", refs[1].url);
    try testing.expectEqual(net.loader.ResourceType.JS, refs[1].type);

    try testing.expectEqualStrings("http://example.com/logo.png", refs[2].url);
    try testing.expectEqual(net.loader.ResourceType.Image, refs[2].type);
}

test "ResourceLoader loadResources prioritizes CSS over JS over Image" {
    var doc = try dom.Document.init(testing.allocator);
    defer doc.deinit();

    const root = try buildTestDom(doc);

    var client = net.fetch.FetchClient.init(testing.allocator, &dummy_bridge);
    const base_url = try net.url.Url.parse("http://example.com/");
    
    var loader = net.loader.ResourceLoader.init(testing.allocator, &client, base_url);
    defer loader.deinit();
    const refs = try loader.discoverResources(root);
    defer testing.allocator.free(refs);
    defer for (refs) |ref| testing.allocator.free(ref.url);

    // startLoading will fetch them asynchronously
    try loader.startLoading(refs);
    
    // In our dummy_bridge, poll immediately returns SUCCESS for all
    const loaded_slice = try loader.poll();
    
    // We need to duplicate the slice and transfer ownership since poll() returns a slice 
    // owned by the loader, to match the test's cleanup expectations, or just not free it here.
    // Actually, loader.deinit() frees the resources inside it. So we just need to let loader defer.
    // We'll just assign it:
    const loaded = loaded_slice;

    try testing.expectEqual(@as(usize, 3), loaded.len);
    
    // priority: CSS -> JS -> Image
    try testing.expectEqual(net.loader.ResourceType.CSS, loaded[0].type);
    try testing.expectEqual(net.loader.ResourceType.JS, loaded[1].type);
    try testing.expectEqual(net.loader.ResourceType.Image, loaded[2].type);
}
