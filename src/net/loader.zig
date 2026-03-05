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
        allocator.free(self.body);
    }
};

pub const ResourceLoader = struct {
    allocator: std.mem.Allocator,
    fetch_client: *fetch.FetchClient,
    base_url: url.Url,

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
    pub fn loadResources(self: *ResourceLoader, refs: []const ResourceRef) ![]LoadedResource {
        var loaded = std.ArrayListUnmanaged(LoadedResource){};
        errdefer {
            for (loaded.items) |*res| res.deinit(self.allocator);
            loaded.deinit(self.allocator);
        }

        // Priority 1: CSS
        for (refs) |ref| {
            if (ref.type == .CSS) try self.loadOne(ref, &loaded);
        }

        // Priority 2: JS
        for (refs) |ref| {
            if (ref.type == .JS) try self.loadOne(ref, &loaded);
        }

        // Priority 3: Images
        for (refs) |ref| {
            if (ref.type == .Image) try self.loadOne(ref, &loaded);
        }

        return try loaded.toOwnedSlice(self.allocator);
    }

    fn loadOne(self: *ResourceLoader, ref: ResourceRef, loaded: *std.ArrayListUnmanaged(LoadedResource)) !void {
        std.debug.print("Fetching resource: {s}...\n", .{ref.url});
        var response = self.fetch_client.fetch(.{ .url = ref.url }) catch |err| {
            std.debug.print("Failed to fetch resource {s}: {}\n", .{ ref.url, err });
            return;
        };

        if (response.status_code == 200) {
            try loaded.append(self.allocator, .{
                .type = ref.type,
                .url = try self.allocator.dupe(u8, ref.url),
                .body = response.body, // Ownership transferred
            });
        } else {
            response.deinit(self.allocator);
            std.debug.print("Failed to fetch resource {s}: HTTP {d}\n", .{ ref.url, response.status_code });
        }
    }
};
