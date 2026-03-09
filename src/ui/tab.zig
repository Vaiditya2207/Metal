const std = @import("std");
const dom = @import("../dom/mod.zig");
const css = @import("../css/mod.zig");
const layout = @import("../layout/mod.zig");
const display_list = @import("../render/display_list.zig");
const js = @import("../js/mod.zig");
const net = @import("../net/mod.zig");

pub const Tab = struct {
    id: usize,
    allocator: std.mem.Allocator,
    url: []const u8,
    title: []const u8,
    favicon_texture: ?*anyopaque = null,
    
    document: ?*dom.Document = null,
    styled_root: ?*css.StyledNode = null,
    layout_root: ?*layout.LayoutBox = null,
    display_list: ?display_list.DisplayList = null,
    stylesheets: std.ArrayListUnmanaged(css.Stylesheet) = .{},
    
    scroll_y: f32 = 0,
    history: std.ArrayListUnmanaged([]const u8) = .{},
    history_idx: usize = 0,
    
    js_ctx: ?js.context.JsContext = null,
    js_runtime: ?js.wiring.JsRuntime = null,
    resource_loader: ?net.loader.ResourceLoader = null,

    pub fn init(allocator: std.mem.Allocator, id: usize, url: []const u8) !*Tab {
        const self = try allocator.create(Tab);
        self.* = .{
            .id = id,
            .allocator = allocator,
            .url = try allocator.dupe(u8, url),
            .title = try allocator.dupe(u8, "New Tab"),
        };
        return self;
    }

    pub fn deinit(self: *Tab) void {
        self.allocator.free(self.url);
        self.allocator.free(self.title);
        if (self.document) |d| d.deinit();
        if (self.styled_root) |sr| {
             var resolver = css.resolver.StyleResolver.init(self.allocator);
             resolver.freeStyledNode(@constCast(sr));
        }
        if (self.layout_root) |lr| {
            lr.deinit(self.allocator);
            self.allocator.destroy(lr);
        }
        if (self.display_list) |*dl| dl.deinit();
        self.stylesheets.deinit(self.allocator);
        
        for (self.history.items) |h| self.allocator.free(h);
        self.history.deinit(self.allocator);
        
        if (self.js_ctx) |*ctx| ctx.deinit();
        if (self.js_runtime) |*rt| rt.deinit(self.allocator, &self.js_ctx.?);
        if (self.resource_loader) |*rl| rl.deinit();
        
        self.allocator.destroy(self);
    }
};
