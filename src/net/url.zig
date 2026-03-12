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

        // Handle protocol-relative URLs (e.g. //www.gstatic.com/...)
        if (std.mem.startsWith(u8, relative, "//")) {
            return try std.fmt.allocPrint(allocator, "{s}:{s}", .{ base.scheme, relative });
        }

        var new_path: []const u8 = undefined;
        var needs_free = false;

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
            needs_free = true;
        }

        // N-1 FIX: Normalize path segments (resolve . and ..)
        const normalized = try normalizePath(allocator, new_path);
        if (needs_free) allocator.free(new_path);
        defer allocator.free(normalized);

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
            normalized,
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

    /// Normalize a URL path by resolving `.` and `..` segments.
    /// e.g. "/a/b/../c/./d" → "/a/c/d"
    fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        // Stack of path segments (pointers into `path` or empty)
        var stack = std.ArrayListUnmanaged([]const u8){};
        defer stack.deinit(allocator);

        var it = std.mem.splitScalar(u8, path, '/');
        while (it.next()) |segment| {
            if (segment.len == 0 or std.mem.eql(u8, segment, ".")) {
                // Skip empty segments (from leading/consecutive slashes) and "."
                continue;
            } else if (std.mem.eql(u8, segment, "..")) {
                // Pop one level (can't go above root)
                if (stack.items.len > 0) {
                    _ = stack.pop();
                }
            } else {
                try stack.append(allocator, segment);
            }
        }

        // Build result: always starts with /
        if (stack.items.len == 0) {
            const result = try allocator.alloc(u8, 1);
            result[0] = '/';
            return result;
        }

        // Calculate total length: leading / + each segment preceded by /
        var total_len: usize = 0;
        for (stack.items) |seg| {
            total_len += 1 + seg.len; // "/" + segment
        }

        const result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;
        for (stack.items) |seg| {
            result[pos] = '/';
            pos += 1;
            @memcpy(result[pos .. pos + seg.len], seg);
            pos += seg.len;
        }

        return result;
    }
};
