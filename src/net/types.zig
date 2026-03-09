const std = @import("std");

/// HTTP Methods supported by the fetch client.
pub const HttpMethod = enum {
    GET,
    POST,
    HEAD,

    pub fn toCString(self: HttpMethod) [*:0]const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .HEAD => "HEAD",
        };
    }
};

/// A single HTTP header name/value pair.
pub const HttpHeader = struct {
    name: []const u8,
    value: []const u8,
};

/// Defines an outbound HTTP request.
pub const HttpRequest = struct {
    url: []const u8,
    method: HttpMethod = .GET,
    headers: []const HttpHeader = &[_]HttpHeader{},
    body: ?[]const u8 = null,
};

/// Defines the result of an HTTP fetch operation.
pub const HttpResponse = struct {
    status_code: u16,
    body: []const u8,
    headers: []HttpHeader = &[_]HttpHeader{},
    final_url: ?[]const u8 = null,

    /// Free the response body and headers.
    pub fn deinit(self: *HttpResponse, allocator: std.mem.Allocator) void {
        if (self.body.len > 0) allocator.free(self.body);
        for (self.headers) |hdr| {
            allocator.free(hdr.name);
            allocator.free(hdr.value);
        }
        if (self.headers.len > 0) allocator.free(self.headers);
        if (self.final_url) |u| allocator.free(u);
    }

    /// Get a response header value by name (case-insensitive).
    pub fn getHeader(self: *const HttpResponse, name: []const u8) ?[]const u8 {
        for (self.headers) |hdr| {
            if (std.ascii.eqlIgnoreCase(hdr.name, name)) return hdr.value;
        }
        return null;
    }
};

/// Errors that can occur during a fetch operation.
pub const FetchError = error{
    InvalidUrl,
    ConnectionFailed,
    Timeout,
    OutOfMemory,
    BridgeError,
    UnknownError,
};
