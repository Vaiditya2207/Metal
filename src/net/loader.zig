const std = @import("std");
const dom = @import("../dom/mod.zig");
const url = @import("url.zig");
const types = @import("types.zig");
const fetch = @import("fetch.zig");

pub const ResourceType = enum {
    CSS,
    JS,
    Image,
};

pub const ResourceRef = struct {
    url: []const u8,
    type: ResourceType,
};

pub const LoadedResource = struct {
    type: ResourceType,
    url: []const u8,
    body: []const u8,

    pub fn deinit(self: *LoadedResource, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.body.len > 0) {
            allocator.free(self.body);
        }
    }
};

pub const PendingResource = struct {
    ref: ResourceRef,
    handle: fetch.FetchHandle,
};

pub const ResourceLoader = struct {
    allocator: std.mem.Allocator,
    fetch_client: *fetch.FetchClient,
    base_url: url.Url,
    pending: std.ArrayListUnmanaged(PendingResource) = .{},
    loaded: std.ArrayListUnmanaged(LoadedResource) = .{},

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

    fn walkDiscover(self: *ResourceLoader, node: *dom.Node, refs: *std.ArrayListUnmanaged(ResourceRef)) !void {
        if (node.node_type == .element) {
            if (node.tag == .link) {
                if (node.getAttribute("rel")) |rel| {
                    if (std.mem.eql(u8, rel, "stylesheet")) {
                        if (node.getAttribute("href")) |href| {
                            const res_url = try url.Url.resolve(self.allocator, self.base_url, href);
                            try refs.append(self.allocator, .{ .url = res_url, .type = .CSS });
                        }
                    }
                }
            } else if (node.tag == .script) {
                if (node.getAttribute("src")) |src| {
                    const res_url = try url.Url.resolve(self.allocator, self.base_url, src);
                    try refs.append(self.allocator, .{ .url = res_url, .type = .JS });
                }
            } else if (node.tag == .img) {
                if (node.getAttribute("src")) |src| {
                    const res_url = try url.Url.resolve(self.allocator, self.base_url, src);
                    try refs.append(self.allocator, .{ .url = res_url, .type = .Image });
                }
            }
        }

        for (node.children.items) |child| {
            try self.walkDiscover(child, refs);
        }
    }

    /// Loads the discovered resources. In this basic MVP, they are loaded synchronously
    /// in priority order (CSS -> JS -> Images), but this can be parallelized later.
    /// Loads the discovered resources asynchronously.


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

    /// Polls pending requests and returns a slice of newly loaded resources.
    /// The caller does NOT own the returned slice, but the resources themselves
    /// are owned by the ResourceLoader until deinit().
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
                        .url = p.ref.url, // Ownership transfers to LoadedResource
                        .body = resp.body,
                    });
                } else {
                    resp.deinit(self.allocator);
                    self.allocator.free(p.ref.url);
                    std.debug.print("Failed to fetch resource {s}: HTTP {d}\n", .{ p.ref.url, resp.status_code });
                }
                
                _ = self.pending.orderedRemove(i);
            } else {
                i += 1;
            }
        }
        
        return self.loaded.items[start_loaded..];
    }
};
