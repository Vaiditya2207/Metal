const std = @import("std");
const testing = std.testing;
const fetch = @import("../../src/net/fetch.zig");
const types = @import("../../src/net/types.zig");
const config = @import("../../src/config.zig");

// --- Mock Bridge ---

var mock_status: fetch.FetchStatus = .PENDING;
var mock_status_code: c_int = 200;
var mock_body: []const u8 = "mock response";
var poll_count: usize = 0;
var start_called: bool = false;
var free_called: bool = false;

fn resetMock() void {
    mock_status = .PENDING;
    mock_status_code = 200;
    mock_body = "mock response";
    poll_count = 0;
    start_called = false;
    free_called = false;
}

fn mock_start(url: [*:0]const u8, method: [*:0]const u8, headers: ?[*]const ?[*:0]const u8, header_count: c_int, body: ?[*]const u8, body_len: c_int) callconv(.c) fetch.FetchHandle {
    _ = url;
    _ = method;
    _ = headers;
    _ = header_count;
    _ = body;
    _ = body_len;
    start_called = true;
    return @ptrFromInt(0xDEADBEEF);
}

fn mock_poll(handle: fetch.FetchHandle) callconv(.c) fetch.FetchStatus {
    _ = handle;
    poll_count += 1;
    // Simulate network delay: complete on 2nd poll
    if (poll_count >= 2 and mock_status == .PENDING) {
        return .SUCCESS;
    }
    return mock_status;
}

fn mock_get_status(handle: fetch.FetchHandle) callconv(.c) c_int {
    _ = handle;
    return mock_status_code;
}

fn mock_get_body(handle: fetch.FetchHandle, out_len: *c_int) callconv(.c) ?[*]const u8 {
    _ = handle;
    out_len.* = @intCast(mock_body.len);
    return mock_body.ptr;
}

fn mock_free(handle: fetch.FetchHandle) callconv(.c) void {
    _ = handle;
    free_called = true;
}

fn mock_get_header(_: fetch.FetchHandle, _: [*:0]const u8, _: [*]u8, _: c_int) callconv(.c) c_int {
    return 0;
}

fn mock_get_header_count(_: fetch.FetchHandle) callconv(.c) c_int {
    return 0;
}

fn mock_get_header_at(_: fetch.FetchHandle, _: c_int, _: [*]u8, _: c_int, _: [*]u8, _: c_int) callconv(.c) c_int {
    return 0;
}

fn mock_get_final_url(_: fetch.FetchHandle, _: [*]u8, _: c_int) callconv(.c) c_int {
    return 0;
}

const mock_bridge = fetch.NetBridge{
    .net_fetch_start = @ptrCast(&mock_start),
    .net_fetch_poll = @ptrCast(&mock_poll),
    .net_fetch_get_status_code = @ptrCast(&mock_get_status),
    .net_fetch_get_body = @ptrCast(&mock_get_body),
    .net_fetch_free = @ptrCast(&mock_free),
    .net_fetch_get_header = @ptrCast(&mock_get_header),
    .net_fetch_get_header_count = @ptrCast(&mock_get_header_count),
    .net_fetch_get_header_at = @ptrCast(&mock_get_header_at),
    .net_fetch_get_final_url = @ptrCast(&mock_get_final_url),
};

// --- Tests ---

test "FetchClient success pipeline" {
    resetMock();
    var client = fetch.FetchClient.init(testing.allocator, &mock_bridge);
    
    var resp = try client.fetch(.{ .url = "http://example.com" });
    defer resp.deinit(testing.allocator);
    
    try testing.expect(start_called);
    try testing.expectEqual(@as(usize, 2), poll_count);
    try testing.expect(free_called);
    try testing.expectEqual(@as(u16, 200), resp.status_code);
    try testing.expectEqualStrings("mock response", resp.body);
}

test "FetchClient handles error status" {
    resetMock();
    mock_status = .ERROR;
    var client = fetch.FetchClient.init(testing.allocator, &mock_bridge);
    
    const err = client.fetch(.{ .url = "http://example.com" });
    try testing.expectError(error.ConnectionFailed, err);
    try testing.expect(start_called);
    try testing.expect(free_called);
}

test "FetchClient respects timeout" {
    resetMock();
    // Never transitions to SUCCESS
    poll_count = 0; 
    
    // Create custom bridge that never completes
    const timeout_bridge = fetch.NetBridge{
        .net_fetch_start = @ptrCast(&mock_start),
        .net_fetch_poll = @ptrCast(&struct { fn poll(h: fetch.FetchHandle) callconv(.c) fetch.FetchStatus { _ = h; return .PENDING; } }.poll),
        .net_fetch_get_status_code = @ptrCast(&mock_get_status),
        .net_fetch_get_body = @ptrCast(&mock_get_body),
        .net_fetch_free = @ptrCast(&mock_free),
        .net_fetch_get_header = @ptrCast(&mock_get_header),
        .net_fetch_get_header_count = @ptrCast(&mock_get_header_count),
        .net_fetch_get_header_at = @ptrCast(&mock_get_header_at),
        .net_fetch_get_final_url = @ptrCast(&mock_get_final_url),
    };

    var client = fetch.FetchClient.init(testing.allocator, &timeout_bridge);
    client.cfg.request_timeout_ms = 5; // 5ms timeout for fast test
    
    const err = client.fetch(.{ .url = "http://bad.com" });
    try testing.expectError(error.Timeout, err);
    try testing.expect(free_called);
}

test "FetchClient extracts response headers" {
    resetMock();

    // Mock bridge that returns 2 headers
    const hdr_bridge = fetch.NetBridge{
        .net_fetch_start = @ptrCast(&mock_start),
        .net_fetch_poll = @ptrCast(&mock_poll),
        .net_fetch_get_status_code = @ptrCast(&mock_get_status),
        .net_fetch_get_body = @ptrCast(&mock_get_body),
        .net_fetch_free = @ptrCast(&mock_free),
        .net_fetch_get_header = @ptrCast(&mock_get_header),
        .net_fetch_get_header_count = @ptrCast(&struct {
            fn f(_: fetch.FetchHandle) callconv(.c) c_int {
                return 2;
            }
        }.f),
        .net_fetch_get_header_at = @ptrCast(&struct {
            fn f(_: fetch.FetchHandle, idx: c_int, on: [*]u8, _: c_int, ov: [*]u8, _: c_int) callconv(.c) c_int {
                const names = [_][]const u8{ "Content-Type", "X-Custom" };
                const vals = [_][]const u8{ "text/html", "hello" };
                const i = @as(usize, @intCast(idx));
                if (i >= 2) return 0;
                @memcpy(on[0..names[i].len], names[i]);
                on[names[i].len] = 0;
                @memcpy(ov[0..vals[i].len], vals[i]);
                ov[vals[i].len] = 0;
                return 1;
            }
        }.f),
        .net_fetch_get_final_url = @ptrCast(&mock_get_final_url),
    };

    var client = fetch.FetchClient.init(testing.allocator, &hdr_bridge);
    var resp = try client.fetch(.{ .url = "http://example.com" });
    defer resp.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), resp.headers.len);
    try testing.expectEqualStrings("Content-Type", resp.headers[0].name);
    try testing.expectEqualStrings("text/html", resp.headers[0].value);
    try testing.expectEqualStrings("X-Custom", resp.headers[1].name);
    try testing.expectEqualStrings("hello", resp.headers[1].value);
}
