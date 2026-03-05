const std = @import("std");
const testing = std.testing;
const types = @import("../../src/net/types.zig");

test "HttpMethod toCString" {
    try testing.expectEqualStrings("GET", std.mem.span(types.HttpMethod.GET.toCString()));
    try testing.expectEqualStrings("POST", std.mem.span(types.HttpMethod.POST.toCString()));
    try testing.expectEqualStrings("HEAD", std.mem.span(types.HttpMethod.HEAD.toCString()));
}

test "HttpRequest default construction" {
    const req = types.HttpRequest{
        .url = "http://example.com",
    };
    try testing.expectEqualStrings("http://example.com", req.url);
    try testing.expectEqual(types.HttpMethod.GET, req.method);
    try testing.expectEqual(@as(usize, 0), req.headers.len);
    try testing.expectEqual(@as(?[]const u8, null), req.body);
}

test "HttpRequest full construction" {
    const headers = [_]types.HttpHeader{
        .{ .name = "Accept", .value = "text/html" },
        .{ .name = "User-Agent", .value = "Metal/0.1" },
    };
    const body = "hello=world";
    const req = types.HttpRequest{
        .url = "https://example.com/api",
        .method = .POST,
        .headers = &headers,
        .body = body,
    };
    try testing.expectEqualStrings("https://example.com/api", req.url);
    try testing.expectEqual(types.HttpMethod.POST, req.method);
    try testing.expectEqual(@as(usize, 2), req.headers.len);
    try testing.expectEqualStrings("Accept", req.headers[0].name);
    try testing.expectEqualStrings("text/html", req.headers[0].value);
    try testing.expectEqualStrings(body, req.body.?);
}

test "HttpResponse deinit frees body" {
    var resp = types.HttpResponse{
        .status_code = 200,
        .body = try testing.allocator.dupe(u8, "response data"),
    };
    try testing.expectEqual(@as(u16, 200), resp.status_code);
    try testing.expectEqualStrings("response data", resp.body);
    // test allocator will catch leaks if deinit fails
    resp.deinit(testing.allocator);
}
