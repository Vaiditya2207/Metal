const std = @import("std");
const testing = std.testing;
const url = @import("../../src/net/url.zig");

test "Url.parse absolute http" {
    const u = try url.Url.parse("http://example.com/path?q=1#frag");
    try testing.expectEqualStrings("http", u.scheme);
    try testing.expectEqualStrings("example.com", u.host);
    try testing.expectEqual(@as(u16, 80), u.port);
    try testing.expectEqualStrings("/path", u.path);
    try testing.expectEqualStrings("q=1", u.query.?);
    try testing.expectEqualStrings("frag", u.fragment.?);
}

test "Url.parse absolute https with port" {
    const u = try url.Url.parse("https://api.github.com:8080/users");
    try testing.expectEqualStrings("https", u.scheme);
    try testing.expectEqualStrings("api.github.com", u.host);
    try testing.expectEqual(@as(u16, 8080), u.port);
    try testing.expectEqualStrings("/users", u.path);
    try testing.expectEqual(@as(?[]const u8, null), u.query);
    try testing.expectEqual(@as(?[]const u8, null), u.fragment);
}

test "Url.parse missing path defaults to slash" {
    const u = try url.Url.parse("https://example.com");
    try testing.expectEqualStrings("https", u.scheme);
    try testing.expectEqualStrings("example.com", u.host);
    try testing.expectEqual(@as(u16, 443), u.port);
    try testing.expectEqualStrings("/", u.path);
}

test "Url.parse unsupported scheme" {
    try testing.expectError(error.UnsupportedScheme, url.Url.parse("ftp://example.com"));
    try testing.expectError(error.UnsupportedScheme, url.Url.parse("file:///path/to/thing"));
}

test "Url.resolve relative to absolute directory" {
    const base = try url.Url.parse("http://example.com/assets/");
    const resolved = try url.Url.resolve(testing.allocator, base, "style.css");
    defer testing.allocator.free(resolved);
    try testing.expectEqualStrings("http://example.com/assets/style.css", resolved);
}

test "Url.resolve relative to absolute file path pops file" {
    const base = try url.Url.parse("http://example.com/assets/index.html");
    const resolved = try url.Url.resolve(testing.allocator, base, "style.css");
    defer testing.allocator.free(resolved);
    try testing.expectEqualStrings("http://example.com/assets/style.css", resolved);
}

test "Url.resolve root-relative path" {
    const base = try url.Url.parse("http://example.com/assets/css/main.css");
    const resolved = try url.Url.resolve(testing.allocator, base, "/images/logo.png");
    defer testing.allocator.free(resolved);
    try testing.expectEqualStrings("http://example.com/images/logo.png", resolved);
}

test "Url.resolve absolute path ignores base" {
    const base = try url.Url.parse("http://example.com/page");
    const resolved = try url.Url.resolve(testing.allocator, base, "https://cdn.example.com/script.js");
    defer testing.allocator.free(resolved);
    try testing.expectEqualStrings("https://cdn.example.com/script.js", resolved);
}

test "Url.format http standard port" {
    const u = url.Url{
        .scheme = "http",
        .host = "example.com",
        .path = "/test",
    };
    const str = try u.format(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("http://example.com/test", str);
}

test "Url.format https custom port with query" {
    const u = url.Url{
        .scheme = "https",
        .host = "example.com",
        .port = 8443,
        .path = "/test",
        .query = "a=b",
    };
    const str = try u.format(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("https://example.com:8443/test?a=b", str);
}
