const std = @import("std");
const dom = @import("../dom/mod.zig");
const url = @import("url.zig");
const types = @import("types.zig");
const fetch = @import("fetch.zig");

pub const ResourceType = enum {
    CSS,
    JS,
    Image,
    Favicon,
};

pub const ResourceRef = struct {
    url: []const u8,
    type: ResourceType,
};

pub const LoadedResource = struct {
    url: []const u8,
    type: ResourceType,
    body: []const u8,

    pub fn deinit(self: *LoadedResource, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.body);
    }
};

const PendingRequest = struct {
    ref: ResourceRef,
    handle: fetch.FetchHandle,
};

pub const ResourceLoader = struct {
    allocator: std.mem.Allocator,
    fetch_client: *fetch.FetchClient,
    base_url: url.Url,
    pending: std.ArrayListUnmanaged(PendingRequest) = .empty,
    loaded: std.ArrayListUnmanaged(LoadedResource) = .empty,

    pub fn init(allocator: std.mem.Allocator, fetch_client: *fetch.FetchClient, base_url: url.Url) ResourceLoader {
        return .{
            .allocator = allocator,
            .fetch_client = fetch_client,
            .base_url = base_url,
        };
    }

    /// Recursively discovers resources in the DOM tree.
    pub fn discoverResources(self: *ResourceLoader, root: *dom.Node) ![]ResourceRef {
        var refs = std.ArrayListUnmanaged(ResourceRef){};
        errdefer {
            for (refs.items) |ref| self.allocator.free(ref.url);
            refs.deinit(self.allocator);
        }
        try self.walkDiscover(root, &refs);
        return try refs.toOwnedSlice(self.allocator);
    }

    fn isGarbled(raw: []const u8) bool {
        if (raw.len == 0) return true;
        if (raw.len > 2000) return true;
        if (std.mem.startsWith(u8, raw, "data:")) return true;
        
        var i: usize = 0;
        while (i < raw.len) {
            const c = raw[i];
            if (c > 127) return true;
            if (c == '%' and i + 2 < raw.len) {
                const h1 = std.fmt.charToDigit(raw[i + 1], 16) catch 0;
                const h2 = std.fmt.charToDigit(raw[i + 2], 16) catch 0;
                const val = (h1 << 4) | h2;
                if (val > 127 or (val < 32 and val != 9 and val != 10 and val != 13)) {
                    return true;
                }
                i += 2;
            }
            i += 1;
        }
        return false;
    }

    fn walkDiscover(self: *ResourceLoader, node: *dom.Node, refs: *std.ArrayListUnmanaged(ResourceRef)) !void {
        if (node.node_type == .element) {
            if (node.tag == .link) {
                if (node.getAttribute("rel")) |rel| {
                    const is_css = std.mem.eql(u8, rel, "stylesheet");
                    const is_favicon = std.mem.eql(u8, rel, "icon") or std.mem.eql(u8, rel, "shortcut icon");
                    if (is_css or is_favicon) {
                        if (node.getAttribute("href")) |href| {
                            try self.addResource(refs, href, if (is_css) .CSS else .Favicon);
                        }
                    }
                }
            } else if (node.tag == .script) {
                if (node.getAttribute("src")) |src| {
                    try self.addResource(refs, src, .JS);
                }
            } else if (node.tag == .img) {
                if (node.getAttribute("src")) |src| {
                    try self.addResource(refs, src, .Image);
                }
            }
        }

        for (node.children.items) |child| {
            try self.walkDiscover(child, refs);
        }
    }

    fn addResource(self: *ResourceLoader, refs: *std.ArrayListUnmanaged(ResourceRef), raw_url: []const u8, res_type: ResourceType) !void {
        if (isGarbled(raw_url)) return;
        const res_url = url.Url.resolve(self.allocator, self.base_url, raw_url) catch |err| {
            std.debug.print("Failed to resolve URL {s}: {}\n", .{ raw_url, err });
            return;
        };
        if (isGarbled(res_url)) {
            self.allocator.free(res_url);
            return;
        }
        try refs.append(self.allocator, .{
            .url = res_url,
            .type = res_type,
        });
    }

    pub fn deinit(self: *ResourceLoader) void {
        for (self.pending.items) |p| {
            self.fetch_client.bridge.net_fetch_free(p.handle);
            self.allocator.free(p.ref.url);
        }
        self.pending.deinit(self.allocator);
        for (self.loaded.items) |*l| l.deinit(self.allocator);
        self.loaded.deinit(self.allocator);
    }

    pub fn startLoading(self: *ResourceLoader, refs: []const ResourceRef) !void {
        for (refs) |ref| {
            if (isGarbled(ref.url)) continue;
            const handle = self.fetch_client.startFetch(.{ .url = ref.url }) catch |err| {
                std.debug.print("Failed to start fetch for {s}: {}\n", .{ref.url, err});
                continue;
            };
            try self.pending.append(self.allocator, .{
                .ref = .{ .url = try self.allocator.dupe(u8, ref.url), .type = ref.type },
                .handle = handle,
            });
        }
    }

    pub fn poll(self: *ResourceLoader) ![]LoadedResource {
        const start_loaded = self.loaded.items.len;
        var i: usize = 0;
        while (i < self.pending.items.len) {
            const p = self.pending.items[i];
            if (self.fetch_client.pollFetch(p.handle) catch null) |r| {
                var resp = r;
                defer self.fetch_client.bridge.net_fetch_free(p.handle);
                if (resp.status_code == 200) {
                    try self.loaded.append(self.allocator, .{
                        .type = p.ref.type,
                        .url = p.ref.url,
                        .body = resp.body,
                    });
                } else {
                    std.debug.print("Failed to fetch resource {s}: HTTP {d}\n", .{ p.ref.url, resp.status_code });
                    resp.deinit(self.allocator);
                    self.allocator.free(p.ref.url);
                }
                _ = self.pending.orderedRemove(i);
            } else {
                i += 1;
            }
        }
        return self.loaded.items[start_loaded..];
    }
};
