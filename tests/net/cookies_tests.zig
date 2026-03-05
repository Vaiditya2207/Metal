const std = @import("std");
const testing = std.testing;
const cookies = @import("../../src/net/cookies.zig");

test "CookieJar addFromHeader basic" {
    var jar = cookies.CookieJar.init(testing.allocator);
    defer jar.deinit();

    try jar.addFromHeader("example.com", "sid=abc123; Path=/; Domain=.example.com");
    try testing.expectEqual(@as(usize, 1), jar.count());
}

test "CookieJar domain matching" {
    var jar = cookies.CookieJar.init(testing.allocator);
    defer jar.deinit();

    try jar.addFromHeader("example.com", "sid=abc; Domain=example.com; Path=/");
    const result = try jar.formatForUrl(testing.allocator, "www.example.com", "/page");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("sid=abc", result);
}

test "CookieJar exact domain match" {
    var jar = cookies.CookieJar.init(testing.allocator);
    defer jar.deinit();

    try jar.addFromHeader("example.com", "tok=xyz; Domain=example.com; Path=/");
    const result = try jar.formatForUrl(testing.allocator, "example.com", "/");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("tok=xyz", result);
}

test "CookieJar no match for different domain" {
    var jar = cookies.CookieJar.init(testing.allocator);
    defer jar.deinit();

    try jar.addFromHeader("example.com", "sid=abc; Domain=example.com; Path=/");
    const result = try jar.formatForUrl(testing.allocator, "other.com", "/");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("", result);
}

test "CookieJar path matching" {
    var jar = cookies.CookieJar.init(testing.allocator);
    defer jar.deinit();

    try jar.addFromHeader("example.com", "a=1; Path=/api");
    const match = try jar.formatForUrl(testing.allocator, "example.com", "/api/data");
    defer testing.allocator.free(match);
    try testing.expectEqualStrings("a=1", match);

    const no_match = try jar.formatForUrl(testing.allocator, "example.com", "/other");
    defer testing.allocator.free(no_match);
    try testing.expectEqualStrings("", no_match);
}

test "CookieJar multiple cookies" {
    var jar = cookies.CookieJar.init(testing.allocator);
    defer jar.deinit();

    try jar.addFromHeader("example.com", "a=1; Domain=example.com; Path=/");
    try jar.addFromHeader("example.com", "b=2; Domain=example.com; Path=/");
    const result = try jar.formatForUrl(testing.allocator, "example.com", "/");
    defer testing.allocator.free(result);
    // Both cookies should be present
    try testing.expect(std.mem.indexOf(u8, result, "a=1") != null);
    try testing.expect(std.mem.indexOf(u8, result, "b=2") != null);
}

test "CookieJar replace existing cookie" {
    var jar = cookies.CookieJar.init(testing.allocator);
    defer jar.deinit();

    try jar.addFromHeader("example.com", "sid=old; Domain=example.com; Path=/");
    try jar.addFromHeader("example.com", "sid=new; Domain=example.com; Path=/");
    try testing.expectEqual(@as(usize, 1), jar.count());

    const result = try jar.formatForUrl(testing.allocator, "example.com", "/");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("sid=new", result);
}

test "CookieJar HttpOnly and Secure flags" {
    var jar = cookies.CookieJar.init(testing.allocator);
    defer jar.deinit();

    try jar.addFromHeader("example.com", "s=v; HttpOnly; Secure; Path=/");
    try testing.expectEqual(@as(usize, 1), jar.count());
    try testing.expect(jar.cookies.items[0].http_only);
    try testing.expect(jar.cookies.items[0].secure);
}

test "CookieJar dot-prefix domain" {
    var jar = cookies.CookieJar.init(testing.allocator);
    defer jar.deinit();

    // Leading dot should be stripped
    try jar.addFromHeader("google.com", "NID=123; Domain=.google.com; Path=/");
    const result = try jar.formatForUrl(testing.allocator, "www.google.com", "/");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("NID=123", result);
}
