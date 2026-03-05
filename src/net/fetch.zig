const std = @import("std");
const types = @import("types.zig");
const config = @import("../config.zig");

pub const FetchHandle = ?*anyopaque;

pub const FetchStatus = enum(c_int) {
    PENDING = 0,
    SUCCESS = 1,
    ERROR = 2,
    TIMEOUT = 3,
};

/// Vtable mirroring the ObjC bridge C functions.
pub const NetBridge = struct {
    net_fetch_start: *const fn ([*:0]const u8, [*:0]const u8, ?[*]const ?[*:0]const u8, c_int, ?[*]const u8, c_int) callconv(.c) FetchHandle,
    net_fetch_poll: *const fn (FetchHandle) callconv(.c) FetchStatus,
    net_fetch_get_status_code: *const fn (FetchHandle) callconv(.c) c_int,
    net_fetch_get_body: *const fn (FetchHandle, *c_int) callconv(.c) ?[*]const u8,
    net_fetch_free: *const fn (FetchHandle) callconv(.c) void,
    net_fetch_get_header: *const fn (FetchHandle, [*:0]const u8, [*]u8, c_int) callconv(.c) c_int,
    net_fetch_get_header_count: *const fn (FetchHandle) callconv(.c) c_int,
    net_fetch_get_header_at: *const fn (FetchHandle, c_int, [*]u8, c_int, [*]u8, c_int) callconv(.c) c_int,
};

pub const FetchClient = struct {
    allocator: std.mem.Allocator,
    bridge: *const NetBridge,
    cfg: config.Config.NetworkConfig,

    pub fn init(allocator: std.mem.Allocator, bridge: *const NetBridge) FetchClient {
        return .{
            .allocator = allocator,
            .bridge = bridge,
            .cfg = config.getConfig().network,
        };
    }

    pub fn fetch(self: *FetchClient, request: types.HttpRequest) !types.HttpResponse {
        const handle = try self.startFetch(request);
        defer self.bridge.net_fetch_free(handle);

        var timer = try std.time.Timer.start();
        const timeout_ns = @as(u64, self.cfg.request_timeout_ms) * 1_000_000;

        while (true) {
            if (try self.pollFetch(handle)) |resp| return resp;
            if (timer.read() > timeout_ns) return error.Timeout;
            std.Thread.sleep(1_000_000); // 1ms
        }
    }

    pub fn startFetch(self: *FetchClient, request: types.HttpRequest) !FetchHandle {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const url_cstr = try arena.allocator().dupeZ(u8, request.url);

        // Prepare headers array for C layer: [name1, val1, name2, val2, ...]
        var header_cstrs = try arena.allocator().alloc(?[*:0]const u8, request.headers.len * 2);
        for (request.headers, 0..) |hdr, i| {
            header_cstrs[i * 2] = try arena.allocator().dupeZ(u8, hdr.name);
            header_cstrs[i * 2 + 1] = try arena.allocator().dupeZ(u8, hdr.value);
        }

        const body_ptr = if (request.body) |body| body.ptr else null;
        const body_len = if (request.body) |body| @as(c_int, @intCast(body.len)) else 0;

        const handle = self.bridge.net_fetch_start(
            url_cstr,
            request.method.toCString(),
            if (header_cstrs.len > 0) @ptrCast(header_cstrs.ptr) else null,
            @as(c_int, @intCast(request.headers.len)),
            body_ptr,
            body_len,
        );

        if (handle == null) return error.BridgeError;
        return handle;
    }

    pub fn pollFetch(self: *FetchClient, handle: FetchHandle) !?types.HttpResponse {
        const status = self.bridge.net_fetch_poll(handle);
        switch (status) {
            .PENDING => return null,
            .ERROR => return error.ConnectionFailed,
            .TIMEOUT => return error.Timeout,
            .SUCCESS => {},
        }

        const status_code = self.bridge.net_fetch_get_status_code(handle);

        var body_len_out: c_int = 0;
        const body_res_ptr = self.bridge.net_fetch_get_body(handle, &body_len_out);

        var response_body: []const u8 = &[_]u8{};
        if (body_res_ptr != null and body_len_out > 0) {
            if (body_len_out > self.cfg.max_response_size_bytes) {
                return error.OutOfMemory;
            }
            const src_slice = body_res_ptr.?[0..@as(usize, @intCast(body_len_out))];
            response_body = try self.allocator.dupe(u8, src_slice);
        }

        const resp_headers = try self.extractHeaders(handle);

        return types.HttpResponse{
            .status_code = @as(u16, @intCast(status_code)),
            .body = response_body,
            .headers = resp_headers,
        };
    }

    fn extractHeaders(self: *FetchClient, handle: FetchHandle) ![]types.HttpHeader {
        const count = self.bridge.net_fetch_get_header_count(handle);
        if (count <= 0) return &[_]types.HttpHeader{};

        const ucount = @as(usize, @intCast(count));
        var headers = try self.allocator.alloc(types.HttpHeader, ucount);
        var actual: usize = 0;

        var name_buf: [512]u8 = undefined;
        var value_buf: [4096]u8 = undefined;

        for (0..ucount) |i| {
            const ok = self.bridge.net_fetch_get_header_at(
                handle,
                @as(c_int, @intCast(i)),
                &name_buf,
                512,
                &value_buf,
                4096,
            );
            if (ok == 1) {
                const nlen = std.mem.indexOfScalar(u8, &name_buf, 0) orelse 0;
                const vlen = std.mem.indexOfScalar(u8, &value_buf, 0) orelse 0;
                headers[actual] = .{
                    .name = try self.allocator.dupe(u8, name_buf[0..nlen]),
                    .value = try self.allocator.dupe(u8, value_buf[0..vlen]),
                };
                actual += 1;
            }
        }

        if (actual < ucount) {
            headers = self.allocator.realloc(headers, actual) catch headers;
        }
        return headers[0..actual];
    }
};

