const std = @import("std");

/// A parsed URL structure.
pub const Url = struct {
    scheme: []const u8 = "http",
    host: []const u8 = "",
    port: u16 = 80,
    path: []const u8 = "/",
    query: ?[]const u8 = null,
    fragment: ?[]const u8 = null,

    /// Parse a complete absolute URL from a string.
    pub fn parse(raw_url: []const u8) !Url {
        var result = Url{};
        var rest = raw_url;

        // Scheme
        if (std.mem.indexOf(u8, rest, "://")) |scheme_end| {
            result.scheme = rest[0..scheme_end];
            rest = rest[scheme_end + 3 ..];
        } else {
            return error.MissingScheme;
        }

        if (!std.mem.eql(u8, result.scheme, "http") and !std.mem.eql(u8, result.scheme, "https")) {
            return error.UnsupportedScheme;
        }

        // Host and Port
        const authority_end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;
        const authority = rest[0..authority_end];
        rest = rest[authority_end..];

        if (std.mem.indexOf(u8, authority, ":")) |colon_idx| {
            result.host = authority[0..colon_idx];
            const port_str = authority[colon_idx + 1 ..];
            result.port = std.fmt.parseInt(u16, port_str, 10) catch return error.InvalidPort;
        } else {
            result.host = authority;
            result.port = if (std.mem.eql(u8, result.scheme, "https")) 443 else 80;
        }

        if (result.host.len == 0) return error.MissingHost;

        // Path, Query, Fragment
        if (rest.len == 0) {
            result.path = "/";
            return result;
        }

        const frag_idx = std.mem.indexOf(u8, rest, "#");
        if (frag_idx) |idx| {
            result.fragment = rest[idx + 1 ..];
            rest = rest[0..idx];
        }

        const query_idx = std.mem.indexOf(u8, rest, "?");
        if (query_idx) |idx| {
            result.query = rest[idx + 1 ..];
            rest = rest[0..idx];
        }

        if (rest.len > 0) {
            result.path = rest;
        }

        return result;
    }

    /// Resolve a relative URL against a base URL.
    pub fn resolve(allocator: std.mem.Allocator, base: Url, relative: []const u8) ![]u8 {
        // If relative is already absolute, just return it
        if (std.mem.startsWith(u8, relative, "http://") or std.mem.startsWith(u8, relative, "https://")) {
            return try allocator.dupe(u8, relative);
        }

        var new_path: []const u8 = undefined;

        if (std.mem.startsWith(u8, relative, "/")) {
            // Absolute path
            new_path = relative;
        } else {
            // Relative path - append to base's directory
            var base_dir = base.path;
            if (std.mem.lastIndexOf(u8, base_dir, "/")) |last_slash| {
                base_dir = base_dir[0 .. last_slash + 1];
            } else {
                base_dir = "/";
            }
            new_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_dir, relative });
            // In a real implementation we'd normalize ../ and ./ here
            // But doing that cleanly requires more memory allocations.
        }

        defer if (!std.mem.startsWith(u8, relative, "/") and new_path.len > 0) allocator.free(new_path);

        const port_str = if ((std.mem.eql(u8, base.scheme, "http") and base.port == 80) or
            (std.mem.eql(u8, base.scheme, "https") and base.port == 443))
            ""
        else
            try std.fmt.allocPrint(allocator, ":{d}", .{base.port});
        defer if (port_str.len > 0) allocator.free(port_str);

        return try std.fmt.allocPrint(allocator, "{s}://{s}{s}{s}", .{
            base.scheme,
            base.host,
            port_str,
            new_path,
        });
    }

    /// Format the URL into an allocated string.
    pub fn format(self: Url, allocator: std.mem.Allocator) ![]u8 {
        const port_str = if ((std.mem.eql(u8, self.scheme, "http") and self.port == 80) or
            (std.mem.eql(u8, self.scheme, "https") and self.port == 443))
            ""
        else
            try std.fmt.allocPrint(allocator, ":{d}", .{self.port});
        defer if (port_str.len > 0) allocator.free(port_str);

        const query_str = if (self.query) |q|
            try std.fmt.allocPrint(allocator, "?{s}", .{q})
        else
            "";
        defer if (query_str.len > 0) allocator.free(query_str);

        return try std.fmt.allocPrint(allocator, "{s}://{s}{s}{s}{s}", .{
            self.scheme,
            self.host,
            port_str,
            self.path,
            query_str,
        });
    }
};
