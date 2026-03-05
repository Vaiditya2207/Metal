const std = @import("std");
const url_mod = @import("url.zig");

pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    domain: []const u8,
    path: []const u8,
    http_only: bool = false,
    secure: bool = false,
};

pub const CookieJar = struct {
    allocator: std.mem.Allocator,
    cookies: std.ArrayListUnmanaged(Cookie),

    pub fn init(allocator: std.mem.Allocator) CookieJar {
        return .{
            .allocator = allocator,
            .cookies = .{},
        };
    }

    pub fn deinit(self: *CookieJar) void {
        for (self.cookies.items) |c| self.freeCookie(c);
        self.cookies.deinit(self.allocator);
    }

    fn freeCookie(self: *CookieJar, c: Cookie) void {
        self.allocator.free(c.name);
        self.allocator.free(c.value);
        self.allocator.free(c.domain);
        self.allocator.free(c.path);
    }

    /// Parse a Set-Cookie header value and add to the jar.
    /// Format: "name=value; Path=/; Domain=.example.com; HttpOnly; Secure"
    pub fn addFromHeader(self: *CookieJar, request_domain: []const u8, header: []const u8) !void {
        // Split on ';' to get attributes
        var name: []const u8 = "";
        var value: []const u8 = "";
        var domain: []const u8 = request_domain;
        var path: []const u8 = "/";
        var http_only = false;
        var secure = false;

        var parts = std.mem.splitScalar(u8, header, ';');
        var first = true;
        while (parts.next()) |raw_part| {
            const part = std.mem.trim(u8, raw_part, " \t");
            if (first) {
                first = false;
                if (std.mem.indexOf(u8, part, "=")) |eq| {
                    name = part[0..eq];
                    value = part[eq + 1 ..];
                } else {
                    return; // Invalid cookie, no name=value
                }
                continue;
            }

            if (std.ascii.eqlIgnoreCase(part, "HttpOnly")) {
                http_only = true;
            } else if (std.ascii.eqlIgnoreCase(part, "Secure")) {
                secure = true;
            } else if (std.mem.indexOf(u8, part, "=")) |eq| {
                const attr_name = std.mem.trim(u8, part[0..eq], " \t");
                const attr_val = std.mem.trim(u8, part[eq + 1 ..], " \t");
                if (std.ascii.eqlIgnoreCase(attr_name, "Domain")) {
                    domain = if (attr_val.len > 0 and attr_val[0] == '.')
                        attr_val[1..]
                    else
                        attr_val;
                } else if (std.ascii.eqlIgnoreCase(attr_name, "Path")) {
                    path = attr_val;
                }
            }
        }

        if (name.len == 0) return;

        // Remove existing cookie with same name+domain
        self.removeCookie(name, domain);

        try self.cookies.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
            .domain = try self.allocator.dupe(u8, domain),
            .path = try self.allocator.dupe(u8, path),
            .http_only = http_only,
            .secure = secure,
        });
    }

    fn removeCookie(self: *CookieJar, name: []const u8, domain: []const u8) void {
        var i: usize = 0;
        while (i < self.cookies.items.len) {
            const c = self.cookies.items[i];
            if (std.mem.eql(u8, c.name, name) and domainMatches(c.domain, domain)) {
                self.freeCookie(c);
                _ = self.cookies.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Format matching cookies as a Cookie header value.
    /// Returns allocated string "name=val; name2=val2" or empty string.
    pub fn formatForUrl(self: *const CookieJar, allocator: std.mem.Allocator, host: []const u8, req_path: []const u8) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(allocator);

        for (self.cookies.items) |c| {
            if (!domainMatches(c.domain, host)) continue;
            if (!std.mem.startsWith(u8, req_path, c.path)) continue;

            if (buf.items.len > 0) {
                try buf.appendSlice(allocator, "; ");
            }
            try buf.appendSlice(allocator, c.name);
            try buf.appendSlice(allocator, "=");
            try buf.appendSlice(allocator, c.value);
        }

        return try allocator.dupe(u8, buf.items);
    }

    pub fn count(self: *const CookieJar) usize {
        return self.cookies.items.len;
    }
};

/// Check if cookie_domain matches the request host.
/// "example.com" matches "example.com" and "www.example.com"
fn domainMatches(cookie_domain: []const u8, host: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(cookie_domain, host)) return true;

    // Cookie domain "example.com" should match "sub.example.com"
    if (host.len > cookie_domain.len) {
        const suffix_start = host.len - cookie_domain.len;
        if (host[suffix_start - 1] == '.') {
            return std.ascii.eqlIgnoreCase(host[suffix_start..], cookie_domain);
        }
    }
    return false;
}
